-- Multi-mode MAME screensaver plugin
-- Modes:
--   "bounce"    - Bouncing PNG "MAME" logo (DVD-style)
--   "starfield" - Classic flying starfield
--   "mystify"   - Bouncing polyline (Mystify-style)
--   "matrix"    - Matrix-style falling characters
--   "fireworks" - Particle fireworks with explosions
--   "plasma"    - Classic plasma effect
--   "random"    - Random mode each activation

local exports = {}
exports.name        = "screensaver"
exports.version     = "0.8"
exports.description = "Multi-mode screensaver"
exports.license     = "GPL-3.0+"
exports.author      = "Inigo Montoya"

local screensaver = exports

----------------------------------------------------------------------
-- SETTINGS (loaded from persistence)
----------------------------------------------------------------------

local settings = {
	debug = false,
	enabled = true,
	mode = "bounce",
	timeout = 60.0,
	
	-- Bounce settings
	logo_speed_x = 0.25,
	logo_speed_y = 0.18,
	
	-- Starfield settings
	star_count = 200,
	star_speed = 0.5,
	
	-- Mystify settings
	mystify_polygons = 2,
	mystify_points = 4,
	mystify_speed = 0.25,
	
	-- Matrix settings
	matrix_columns = 120,
	matrix_speed = 0.5,
	
	-- Fireworks settings
	fireworks_launch_rate = 0.5,
	
	-- Plasma settings
	plasma_speed = 2.0,
	plasma_palette = "rainbow"
}

----------------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------------

-- All modes we can randomize between
local AVAILABLE_MODES = { "bounce", "starfield", "mystify", "matrix", "fireworks", "plasma" }

-- The mode actually in use for this screensaver run
local current_mode = nil

local SCREEN_ASPECT_RATIO = nil

-- Bouncing logo config (used in "bounce" mode)
local LOGO_IMAGE_PATH = "plugins/screensaver/mame_logo.png"
local LOGO_SCALE = 0.25

-- General colors
local COLOR_BLACK = 0xFF000000

local LOGO_COLORS = {
    0xFFFFCC00, 0xFF00CCFF, 0xFFFF3366,
    0xFF66FF66, 0xFFCC66FF, 0xFFFFFF66, 0xFF66CCFF,
}

local FALLBACK_TEXT       = "MAME"
local FALLBACK_TEXT_COLOR = 0xFFFFFFFF

-- Starfield constants
local STAR_SPREAD  = 0.3
local STAR_BASE_SIZE   = 0.001
local STAR_MIN_SIZE    = 0.0005
local STAR_MAX_SIZE    = 0.001

-- Mystify constants
local MYSTIFY_TRAIL_LENGTH = 10
local MYSTIFY_SPEED_VARIATION = 0.1

-- Matrix constants
local MATRIX_SPAWN_RATE = 0.10
local MATRIX_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*(){}[]<>/\\|~`+-=;:,.!? "
local MATRIX_COLOR_HEAD = 0xFFFFFFFF
local MATRIX_COLOR_BODY = 0xFF00FF00
local MATRIX_COLOR_FADE = 0xFF004400

-- Fireworks constants
local FIREWORKS_PARTICLES_PER_EXPLOSION = 50
local FIREWORKS_GRAVITY = 0.3
local FIREWORKS_PARTICLE_LIFE = 2.0
local FIREWORKS_PARTICLE_SIZE = 0.001

-- Plasma constants
local PLASMA_RESOLUTION = 60

----------------------------------------------------------------------
-- INTERNAL STATE
----------------------------------------------------------------------

local frame_subscription       = nil
local frame_done_subscription  = nil
local reset_subscription       = nil
local stop_subscription        = nil

local last_active_time    = 0
local screensaver_active  = false
local was_paused_by_us    = false

-- Test mode state
local test_mode_active = false
local test_mode = nil
local test_mode_wait_for_release = false

-- Menu handler
local menu_handler = nil


-- Input detection
local input_types_to_check = nil
local host_codes_to_check  = nil

-- Bounce mode state
local logo_x, logo_y       = 0.0, 0.0
local logo_vx, logo_vy     = 0.0, 0.0
local logo_color_i         = 1
local logo_bitmap          = nil
local logo_texture         = nil
local logo_texture_ok      = false
local logo_width           = 0.25  -- Will be set from image
local logo_height          = 0.133 -- Will be set from image

-- Starfield state
local stars                = {}

-- Mystify state
local mystify_points       = {}
local mystify_history      = {}
local mystify_color_i      = 1

-- Matrix state
local matrix_columns       = {}

-- Fireworks state
local fireworks_rockets    = {}
local fireworks_particles  = {}
local fireworks_next_launch = 0

-- Plasma state
local plasma_time = 0

-- Shared animation timing (real time)
local last_anim_time       = nil

-- Debug counter
local debug_counter        = 0

----------------------------------------------------------------------
-- UTILS
----------------------------------------------------------------------

local function dprint(msg)
    if settings.debug then
        print("[SCREENSAVER] " .. msg)
    end
end

local function detect_screen_aspect_ratio()
    local render = manager.machine.render
    if not render then 
        dprint("No render manager, using default 16:9")
        return 16.0 / 9.0
    end
    
    local target = render.targets[1]
    if not target then 
        dprint("No render target, using default 16:9")
        return 16.0 / 9.0
    end
    
    if target.width and target.height and target.height > 0 then
        local aspect = target.width / target.height
        dprint(string.format("Detected screen aspect ratio: %.2f (%dx%d)", 
            aspect, target.width, target.height))
        return aspect
    end
    
    dprint("Could not detect aspect ratio, using default 16:9")
    return 16.0 / 9.0
end

local function cycle_logo_color()
    logo_color_i = logo_color_i + 1
    if logo_color_i > #LOGO_COLORS then
        logo_color_i = 1
    end
end

local function get_mode_color()
    return LOGO_COLORS[logo_color_i] or 0xFFFFFFFF
end

local function random_char()
    local idx = math.random(1, #MATRIX_CHARS)
    return MATRIX_CHARS:sub(idx, idx)
end

-- Random mode helpers
local random_seeded = false

local function ensure_random_seeded()
    if not random_seeded then
        math.randomseed(os.time())
        math.random()
        math.random()
        math.random()
        random_seeded = true
    end
end

local function pick_random_mode()
    ensure_random_seeded()
    return AVAILABLE_MODES[math.random(1, #AVAILABLE_MODES)]
end

----------------------------------------------------------------------
-- INPUT DETECTION
----------------------------------------------------------------------

local HOST_TOKENS_TO_CHECK = {
    "JOYCODE_1_BUTTON1", "JOYCODE_1_BUTTON2", "JOYCODE_1_BUTTON3",
    "JOYCODE_1_BUTTON4", "JOYCODE_1_BUTTON5", "JOYCODE_1_BUTTON6",
    "JOYCODE_1_YAXIS_UP_SWITCH", "JOYCODE_1_YAXIS_DOWN_SWITCH",
    "JOYCODE_1_XAXIS_LEFT_SWITCH", "JOYCODE_1_XAXIS_RIGHT_SWITCH",
    "JOYCODE_2_BUTTON1", "JOYCODE_2_BUTTON2", "JOYCODE_2_BUTTON3",
    "JOYCODE_2_BUTTON4", "JOYCODE_2_BUTTON5", "JOYCODE_2_BUTTON6",
    "JOYCODE_2_YAXIS_UP_SWITCH", "JOYCODE_2_YAXIS_DOWN_SWITCH",
    "JOYCODE_2_XAXIS_LEFT_SWITCH", "JOYCODE_2_XAXIS_RIGHT_SWITCH",
    "KEYCODE_UP", "KEYCODE_DOWN", "KEYCODE_LEFT", "KEYCODE_RIGHT",
    "KEYCODE_LCONTROL", "KEYCODE_LALT", "KEYCODE_SPACE", "KEYCODE_LSHIFT",
    "KEYCODE_Z", "KEYCODE_X", "KEYCODE_1", "KEYCODE_5",
    "KEYCODE_R", "KEYCODE_F", "KEYCODE_D", "KEYCODE_G",
    "KEYCODE_A", "KEYCODE_S", "KEYCODE_Q", "KEYCODE_W",
    "KEYCODE_I", "KEYCODE_K", "KEYCODE_2", "KEYCODE_6",
    "KEYCODE_ESC", "KEYCODE_ENTER", "KEYCODE_TAB", "KEYCODE_P",
}

local function build_input_types()
    local types = {}
    local ioport = manager.machine.ioport
    if not ioport then return types end

    for _, port in pairs(ioport.ports) do
        for _, field in pairs(port.fields) do
            if field.is_analog then
                table.insert(types, {
                    field    = field,
                    analog   = true,
                    defvalue = field.defvalue
                })
            elseif field.type_class then
                local cls = field.type_class
                if cls == "keyboard" or cls == "controller" or cls == "misc" then
                    table.insert(types, {
                        field  = field,
                        analog = false,
                        type   = field.type,
                        player = field.player
                    })
                end
            end
        end
    end

    dprint(string.format("Monitoring %d emulated input fields", #types))
    return types
end

local function build_host_codes()
    host_codes_to_check = {}
    local inputmgr = manager.machine.input
    if not inputmgr then
        dprint("No input manager, host codes disabled")
        return
    end

    for _, tok in ipairs(HOST_TOKENS_TO_CHECK) do
        local code = inputmgr:code_from_token(tok)
        if code ~= nil then
            table.insert(host_codes_to_check, code)
        end
    end
end

local function is_any_input_pressed()
    local ioport = manager.machine.ioport
    if ioport then
        if not input_types_to_check then
            input_types_to_check = build_input_types()
        end

        for _, input_info in ipairs(input_types_to_check) do
            if input_info.analog then
                local field = input_info.field
                if field.live then
                    local current = field.live.value
                    local default = input_info.defvalue
                    if math.abs(current - default) > 5 then
                        return true
                    end
                end
            else
                if ioport:type_pressed(input_info.type, input_info.player) then
                    return true
                end
            end
        end
    end

    local inputmgr = manager.machine.input
    if inputmgr then
        if not host_codes_to_check then
            build_host_codes()
        end

        if host_codes_to_check then
            for _, code in ipairs(host_codes_to_check) do
                if inputmgr:code_pressed(code) then
                    return true
                end
            end
        end
    end

    return false
end

----------------------------------------------------------------------
-- BOUNCE MODE
----------------------------------------------------------------------

local function load_logo_texture()
    if logo_texture and logo_texture.valid then
        logo_texture_ok = true
        return true
    end

    local f = io.open(LOGO_IMAGE_PATH, "rb")
    if not f then
        dprint("Could not load logo image from: " .. LOGO_IMAGE_PATH)
        logo_texture_ok = false
        return false
    end

    local data = f:read("*a")
    f:close()
    local ok, bmp = pcall(emu.bitmap_argb32.load, data)
    if not ok or not bmp or not bmp.valid then
        dprint("Failed to parse logo bitmap")
        logo_texture_ok = false
        return false
    end

    logo_bitmap = bmp
    
	-- Auto-detect dimensions and maintain aspect ratio
	if bmp.width and bmp.height and bmp.height > 0 and SCREEN_ASPECT_RATIO then
		local image_aspect = bmp.width / bmp.height
		logo_width = settings.logo_scale  -- Use settings instead of LOGO_SCALE
		-- Correct for screen aspect ratio to maintain image proportions
		logo_height = (settings.logo_scale / image_aspect) * SCREEN_ASPECT_RATIO
		dprint(string.format("Logo dimensions: %dx%d, aspect: %.2f, screen aspect: %.2f, display size: %.3fx%.3f", 
			bmp.width, bmp.height, image_aspect, SCREEN_ASPECT_RATIO, logo_width, logo_height))
	else
		-- Fallback to defaults
		logo_width = 0.25
		logo_height = 0.133
		dprint("Could not detect logo dimensions, using defaults")
	end
    
    local render = manager.machine.render
    if not render then
        dprint("No render available")
        logo_texture_ok = false
        return false
    end

    local tex = render:texture_alloc(logo_bitmap)
    if not tex or not tex.valid then
        dprint("Failed to allocate texture")
        logo_texture_ok = false
        return false
    end

    logo_texture    = tex
    logo_texture_ok = true
    dprint("Logo texture loaded successfully!")
    return true
end

local function free_logo_texture()
    if logo_texture and logo_texture.valid then
        logo_texture:free()
    end
    logo_texture    = nil
    logo_bitmap     = nil
    logo_texture_ok = false
end

local function reset_logo_position()
    logo_x = (1.0 - logo_width)  * 0.5
    logo_y = (1.0 - logo_height) * 0.5
    logo_vx = settings.logo_speed_x
    logo_vy = settings.logo_speed_y
    logo_color_i = 1
end

local function update_logo(dt)
    logo_x = logo_x + logo_vx * dt
    logo_y = logo_y + logo_vy * dt

    local bounced = false

    if logo_x < 0 then
        logo_x = 0
        logo_vx = -logo_vx
        bounced = true
    elseif logo_x + logo_width > 1 then
        logo_x = 1 - logo_width
        logo_vx = -logo_vx
        bounced = true
    end

    if logo_y < 0 then
        logo_y = 0
        logo_vy = -logo_vy
        bounced = true
    elseif logo_y + logo_height > 1 then
        logo_y = 1 - logo_height
        logo_vy = -logo_vy
        bounced = true
    end

    if bounced then
        cycle_logo_color()
    end
end

local function draw_bounce(ui)
    local x0 = logo_x
    local y0 = logo_y
    local x1 = logo_x + logo_width
    local y1 = logo_y + logo_height

    if logo_texture_ok and logo_texture and logo_texture.valid then
        local tint = get_mode_color()
        ui:draw_quad(logo_texture, x0, y0, x1, y1, tint)
    else
        local fill = get_mode_color()
        ui:draw_box(x0, y0, x1, y1, fill, fill)
        local text_x = x0 + logo_width * 0.5
        local text_y = y0 + logo_height * 0.5
        ui:draw_text(text_x, text_y, FALLBACK_TEXT, FALLBACK_TEXT_COLOR, 0x00000000)
    end
end

----------------------------------------------------------------------
-- STARFIELD MODE
----------------------------------------------------------------------

local function init_starfield()
    stars = {}
    for i = 1, settings.star_count do
        local star = {
            x = (math.random() * 2 - 1),
            y = (math.random() * 2 - 1),
            z = math.random()
        }
        table.insert(stars, star)
    end
    logo_color_i = 1
end

local function update_starfield(dt)
    for _, star in ipairs(stars) do
        star.z = star.z - settings.star_speed * dt
        if star.z <= 0.05 then
            star.x = (math.random() * 2 - 1)
            star.y = (math.random() * 2 - 1)
            star.z = 1
        end
    end
end

local function draw_starfield(ui)
    for _, star in ipairs(stars) do
        local invz = 1.0 / star.z
        
        local sx = 0.5 + star.x * invz * STAR_SPREAD
        local sy = 0.5 + (star.y / SCREEN_ASPECT_RATIO) * invz * STAR_SPREAD

        local size = STAR_BASE_SIZE * invz
        if size < STAR_MIN_SIZE then size = STAR_MIN_SIZE end
        if size > STAR_MAX_SIZE then size = STAR_MAX_SIZE end

        local distance_factor = 1.0 - star.z
        local brightness = distance_factor * distance_factor
        local min_intensity = 0.5
        local intensity = min_intensity + (brightness * (1.0 - min_intensity))
        local gray = math.floor(intensity * 255)
        local color = 0xFF000000 + (gray * 0x10000) + (gray * 0x100) + gray

        local half_size = size * 0.5
        local x0 = sx - half_size
        local y0 = sy - half_size
        local x1 = sx + half_size
        local y1 = sy + half_size

        if x1 >= 0 and x0 <= 1 and y1 >= 0 and y0 <= 1 then
            ui:draw_box(x0, y0, x1, y1, color, color)
        end
    end
end

----------------------------------------------------------------------
-- MYSTIFY MODE
----------------------------------------------------------------------

local function init_mystify()
    mystify_points = {}
    mystify_history = {}
    
    for poly = 1, settings.mystify_polygons do
        local polygon = {
            color_index = math.random(1, #LOGO_COLORS),
            points = {}
        }
        
        for i = 1, settings.mystify_points do
            local p = {
                x  = math.random(),
                y  = math.random(),
                vx = (math.random() * 2 - 1) * settings.mystify_speed,
                vy = (math.random() * 2 - 1) * settings.mystify_speed
            }
            table.insert(polygon.points, p)
        end
        
        table.insert(mystify_points, polygon)
    end
    
    logo_color_i = 1
end

local function update_mystify(dt)
    for _, polygon in ipairs(mystify_points) do
        local bounced = false
        
        for _, p in ipairs(polygon.points) do
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt

            if p.x < 0 then
                p.x = 0
                p.vx = -p.vx
                p.vx = p.vx * (1.0 + (math.random() * 2 - 1) * MYSTIFY_SPEED_VARIATION)
                bounced = true
            elseif p.x > 1 then
                p.x = 1
                p.vx = -p.vx
                p.vx = p.vx * (1.0 + (math.random() * 2 - 1) * MYSTIFY_SPEED_VARIATION)
                bounced = true
            end

            if p.y < 0 then
                p.y = 0
                p.vy = -p.vy
                p.vy = p.vy * (1.0 + (math.random() * 2 - 1) * MYSTIFY_SPEED_VARIATION)
                bounced = true
            elseif p.y > 1 then
                p.y = 1
                p.vy = -p.vy
                p.vy = p.vy * (1.0 + (math.random() * 2 - 1) * MYSTIFY_SPEED_VARIATION)
                bounced = true
            end
        end
        
        if bounced then
            polygon.color_index = polygon.color_index + 1
            if polygon.color_index > #LOGO_COLORS then
                polygon.color_index = 1
            end
        end
    end
    
    local snapshot = {}
    for poly_idx, polygon in ipairs(mystify_points) do
        local poly_snap = {
            color_index = polygon.color_index,
            points = {}
        }
        for _, p in ipairs(polygon.points) do
            table.insert(poly_snap.points, {x = p.x, y = p.y})
        end
        snapshot[poly_idx] = poly_snap
    end
    table.insert(mystify_history, snapshot)
    
    while #mystify_history > MYSTIFY_TRAIL_LENGTH do
        table.remove(mystify_history, 1)
    end
end

local function draw_mystify(ui)
    for hist_idx, hist_snapshot in ipairs(mystify_history) do
        local age = #mystify_history - hist_idx
        local alpha = math.floor(255 * (1.0 - age / MYSTIFY_TRAIL_LENGTH))
        
        for _, hist_polygon in ipairs(hist_snapshot) do
            if #hist_polygon.points >= 2 then
                local base_color = LOGO_COLORS[hist_polygon.color_index] or 0xFFFFFFFF
                local faded_color = (alpha * 0x1000000) + (base_color & 0x00FFFFFF)
                
                for i = 1, #hist_polygon.points do
                    local p1 = hist_polygon.points[i]
                    local p2 = hist_polygon.points[(i % #hist_polygon.points) + 1]
                    ui:draw_line(p1.x, p1.y, p2.x, p2.y, faded_color)
                end
            end
        end
    end
    
    for _, polygon in ipairs(mystify_points) do
        if #polygon.points >= 2 then
            local color = LOGO_COLORS[polygon.color_index] or 0xFFFFFFFF
            for i = 1, #polygon.points do
                local p1 = polygon.points[i]
                local p2 = polygon.points[(i % #polygon.points) + 1]
                ui:draw_line(p1.x, p1.y, p2.x, p2.y, color)
            end
        end
    end
end

----------------------------------------------------------------------
-- MATRIX MODE
----------------------------------------------------------------------

local function init_matrix()
    matrix_columns = {}
    local col_width = 1.0 / settings.matrix_columns
    
    for i = 1, settings.matrix_columns do
        matrix_columns[i] = {
            x = (i - 0.5) * col_width,
            active = false,
            y = 0,
            speed = 0.3 + math.random() * 0.4,
            length = 20 + math.random(40),
            chars = {}
        }
    end
end

local function update_matrix(dt)
    local col_width = 1.0 / settings.matrix_columns
    local char_height = col_width * 1.5
    
    for _, col in ipairs(matrix_columns) do
        if not col.active and math.random() < MATRIX_SPAWN_RATE then
            col.active = true
            col.y = 0
            -- Remove: col.length = 10 + math.random(20)  -- This was overriding init_matrix!
            col.chars = {}
            for j = 1, col.length do  -- Use the length already set in init_matrix
                col.chars[j] = random_char()
            end
        end
        
        if col.active then
            col.y = col.y + (col.speed * settings.matrix_speed) * dt
            
            if #col.chars > 0 and math.random() < 0.1 then
                local idx = math.random(1, #col.chars)
                col.chars[idx] = random_char()
            end
            
            if col.y - col.length * char_height > 1.0 then
                col.active = false
            end
        end
    end
end

local function draw_matrix(ui)
    local col_width = 1.0 / settings.matrix_columns
    local char_height = col_width * 1.5
    
    for _, col in ipairs(matrix_columns) do
        if col.active then
            for i = 1, #col.chars do
                local char_y = col.y - (i - 1) * char_height
                
                if char_y >= 0 and char_y <= 1.0 then
                    local color
				if i == 1 then
					color = MATRIX_COLOR_HEAD  -- Bright head
				elseif i <= 8 then  -- Extended bright body (was <5)
					color = MATRIX_COLOR_BODY
				else
					local len = #col.chars
					if len > 8 then
						local fade_start = 8
						local fade = 1.0 - ((i - fade_start) / (len - fade_start)) * 0.7  -- Slower fade (only to 30% instead of 0%)
						if fade < 0.3 then fade = 0.3 end  -- Minimum brightness
						local green = math.floor(fade * 255)
						color = 0xFF000000 + (green * 0x100)
					else
						color = MATRIX_COLOR_BODY
					end
				end
                    ui:draw_text(col.x, char_y, col.chars[i], color, 0x00000000)
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- FIREWORKS MODE
----------------------------------------------------------------------

local function init_fireworks()
    fireworks_rockets = {}
    fireworks_particles = {}
    fireworks_next_launch = 0
end

local function update_fireworks(dt)
    fireworks_next_launch = fireworks_next_launch - dt
    if fireworks_next_launch <= 0 then
        fireworks_next_launch = 1.0 / settings.fireworks_launch_rate
        
        local rocket = {
            x = 0.2 + math.random() * 0.6,
            y = 1.0,
            vx = (math.random() * 2 - 1) * 0.1,
            vy = -0.5 - math.random() * 0.3,
            color = LOGO_COLORS[math.random(1, #LOGO_COLORS)],
            exploded = false
        }
        table.insert(fireworks_rockets, rocket)
    end
    
    local i = 1
    while i <= #fireworks_rockets do
        local r = fireworks_rockets[i]
        
        if not r.exploded then
            r.x = r.x + r.vx * dt
            r.y = r.y + r.vy * dt
            r.vy = r.vy + FIREWORKS_GRAVITY * dt
            
            if r.vy > 0 or (r.y < 0.5 and math.random() < 0.02) then
                r.exploded = true
                
                for j = 1, FIREWORKS_PARTICLES_PER_EXPLOSION do
                    local angle = (j / FIREWORKS_PARTICLES_PER_EXPLOSION) * math.pi * 2
                    local speed = 0.2 + math.random() * 0.3
                    
                    local particle = {
                        x = r.x,
                        y = r.y,
                        vx = (math.cos(angle) * speed) / SCREEN_ASPECT_RATIO,
                        vy = math.sin(angle) * speed,
                        color = r.color,
                        life = FIREWORKS_PARTICLE_LIFE,
                        max_life = FIREWORKS_PARTICLE_LIFE
                    }
                    table.insert(fireworks_particles, particle)
                end
                
                table.remove(fireworks_rockets, i)
                i = i - 1
            end
        end
        
        i = i + 1
    end
    
    i = 1
    while i <= #fireworks_particles do
        local p = fireworks_particles[i]
        
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + FIREWORKS_GRAVITY * dt
        p.life = p.life - dt
        
        if p.life <= 0 or p.x < 0 or p.x > 1.0 or p.y < 0 or p.y > 1.0 then
            table.remove(fireworks_particles, i)
            i = i - 1
        end
        
        i = i + 1
    end
end

local function draw_fireworks(ui)
    for _, r in ipairs(fireworks_rockets) do
        if not r.exploded then
            local size = FIREWORKS_PARTICLE_SIZE * 2
            local half_w = size / SCREEN_ASPECT_RATIO
            local half_h = size
            ui:draw_box(r.x - half_w, r.y - half_h, r.x + half_w, r.y + half_h, r.color, r.color)
        end
    end
    
    for _, p in ipairs(fireworks_particles) do
        local alpha = math.floor((p.life / p.max_life) * 255)
        local faded_color = (alpha * 0x1000000) + (p.color & 0x00FFFFFF)
        
        local half_w = FIREWORKS_PARTICLE_SIZE / SCREEN_ASPECT_RATIO
        local half_h = FIREWORKS_PARTICLE_SIZE
        ui:draw_box(p.x - half_w, p.y - half_h, p.x + half_w, p.y + half_h, faded_color, faded_color)
    end
end

----------------------------------------------------------------------
-- PLASMA MODE
----------------------------------------------------------------------

local function init_plasma()
    plasma_time = 0
end

local function update_plasma(dt)
    plasma_time = plasma_time + dt * settings.plasma_speed
end

local function plasma_color_rainbow(value)
    local normalized = (value + 1.0) * 0.5
    local hue = normalized * 6.0
    
    local r, g, b
    if hue < 1 then
        r, g, b = 255, math.floor(hue * 255), 0
    elseif hue < 2 then
        r, g, b = math.floor((2 - hue) * 255), 255, 0
    elseif hue < 3 then
        r, g, b = 0, 255, math.floor((hue - 2) * 255)
    elseif hue < 4 then
        r, g, b = 0, math.floor((4 - hue) * 255), 255
    elseif hue < 5 then
        r, g, b = math.floor((hue - 4) * 255), 0, 255
    else
        r, g, b = 255, 0, math.floor((6 - hue) * 255)
    end
    
    return 0xFF000000 + (r * 0x10000) + (g * 0x100) + b
end

local function plasma_color_fire(value)
    local intensity = (value + 1.0) * 0.5
    intensity = intensity * intensity
    
    local r = math.floor(math.min(intensity * 1.5, 1.0) * 255)
    local g = math.floor(math.max((intensity - 0.3) * 1.4, 0) * 255)
    local b = math.floor(math.max((intensity - 0.7) * 3, 0) * 255)
    return 0xFF000000 + (r * 0x10000) + (g * 0x100) + b
end

local function plasma_color_ocean(value)
    local intensity = (value + 1.0) * 0.5
    intensity = 0.3 + intensity * 0.7
    
    local r = math.floor(math.max((intensity - 0.7) * 3, 0) * 255)
    local g = math.floor(intensity * 0.9 * 255)
    local b = math.floor(255 - (1.0 - intensity) * 80)
    return 0xFF000000 + (r * 0x10000) + (g * 0x100) + b
end

local function plasma_color_matrix(value)
    local intensity = (value + 1.0) * 0.5
    intensity = intensity * intensity * 0.8 + 0.2
    
    local r = 0
    local g = math.floor(intensity * 255)
    local b = math.floor(intensity * 40)
    return 0xFF000000 + (r * 0x10000) + (g * 0x100) + b
end

local function get_plasma_color(value)
    if settings.plasma_palette == "fire" then
        return plasma_color_fire(value)
    elseif settings.plasma_palette == "ocean" then
        return plasma_color_ocean(value)
    elseif settings.plasma_palette == "matrix" then
        return plasma_color_matrix(value)
    else
        return plasma_color_rainbow(value)
    end
end

local function draw_plasma(ui)
    local cols = PLASMA_RESOLUTION
    local rows = math.floor(PLASMA_RESOLUTION / SCREEN_ASPECT_RATIO + 0.5)
    if rows < 1 then rows = 1 end

    local cell_w = 1.0 / cols
    local cell_h = 1.0 / rows

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x = (col / cols) * 2 - 1
            local y = (row / rows) * 2 - 1
            
            local value = 0
            value = value + math.sin(x * 3.0 + plasma_time)
            value = value + math.sin(y * 4.0 + plasma_time * 1.3)
            value = value + math.sin((x + y) * 2.5 + plasma_time * 0.7)
            local dist = math.sqrt(x * x + y * y)
            value = value + math.sin(dist * 5.0 + plasma_time * 1.5)
            value = value + math.sin((x - y) * 3.0 - plasma_time * 0.9)
            value = value / 5.0

            local color = get_plasma_color(value)

            local x0 = col * cell_w
            local y0 = row * cell_h
            local x1 = x0 + cell_w
            local y1 = y0 + cell_h

            ui:draw_box(x0, y0, x1, y1, color, color)
        end
    end
end

----------------------------------------------------------------------
-- ANIMATION DISPATCH
----------------------------------------------------------------------

local function reset_animation_state()
    last_anim_time = os.clock()
end

local function init_mode()
    if settings.mode == "random" then
        current_mode = pick_random_mode()
    else
        current_mode = settings.mode
    end

    dprint("Initializing mode: " .. tostring(current_mode))

    if current_mode == "bounce" then
        reset_logo_position()
        load_logo_texture()
    elseif current_mode == "starfield" then
        free_logo_texture()
        init_starfield()
    elseif current_mode == "mystify" then
        free_logo_texture()
        init_mystify()
    elseif current_mode == "matrix" then
        free_logo_texture()
        init_matrix()
    elseif current_mode == "fireworks" then
        free_logo_texture()
        init_fireworks()
    elseif current_mode == "plasma" then
        free_logo_texture()
        init_plasma()
    end

    reset_animation_state()
end

local function update_animation()
    local now = os.clock()
    if not last_anim_time then 
        last_anim_time = now 
        return
    end
    
    local dt = now - last_anim_time
    last_anim_time = now
    
    if dt > 0.1 then dt = 0.1 end
    if dt <= 0 then dt = 0.016 end

    if current_mode == "bounce" then
        update_logo(dt)
    elseif current_mode == "starfield" then
        update_starfield(dt)
    elseif current_mode == "mystify" then
        update_mystify(dt)
    elseif current_mode == "matrix" then
        update_matrix(dt)
    elseif current_mode == "fireworks" then
        update_fireworks(dt)
    elseif current_mode == "plasma" then
        update_plasma(dt)
    end
end

local function draw_mode(ui_container)
    if current_mode == "bounce" then
        draw_bounce(ui_container)
    elseif current_mode == "starfield" then
        draw_starfield(ui_container)
    elseif current_mode == "mystify" then
        draw_mystify(ui_container)
    elseif current_mode == "matrix" then
        draw_matrix(ui_container)
    elseif current_mode == "fireworks" then
        draw_fireworks(ui_container)
    elseif current_mode == "plasma" then
        draw_plasma(ui_container)
    end
end

----------------------------------------------------------------------
-- SCREENSAVER CONTROL
----------------------------------------------------------------------

local function activate_screensaver()
    dprint("Activating screensaver (config: " .. settings.mode .. ")")
    screensaver_active = true
    init_mode()
    dprint("Using mode: " .. tostring(current_mode))

    local machine = manager.machine
    if machine and not machine.paused then
        emu.pause()
        was_paused_by_us = true
        dprint("Machine paused")
    else
        was_paused_by_us = false
    end
end

local function deactivate_screensaver()
    dprint("Deactivating screensaver")
    screensaver_active = false

    if was_paused_by_us then
        emu.unpause()
        was_paused_by_us = false
        dprint("Machine resumed")
    end
end

----------------------------------------------------------------------
-- FRAME / DRAW CALLBACKS
----------------------------------------------------------------------

local function draw_screensaver_overlay()
    if not screensaver_active then return end

    local render = manager.machine.render
    if not render then return end

    local target = render.targets[1]
    if not target then return end

    local ui_container = target.ui_container
    if not ui_container then return end

    update_animation()
    ui_container:draw_box(0, 0, 1, 1, COLOR_BLACK, COLOR_BLACK)
    draw_mode(ui_container)
end

local function process_frame()
	-- Handle test mode
	if test_mode_active then
		local input_pressed = is_any_input_pressed()
		
		-- Wait for all inputs to be released before monitoring for exit
		if test_mode_wait_for_release then
			if not input_pressed then
				test_mode_wait_for_release = false
				dprint("Test mode ready - press any button to exit")
			end
			return
		end
		
		-- Now monitor for input to exit test mode
		if input_pressed then
			if screensaver_active then
				deactivate_screensaver()
			end
			test_mode_active = false
			test_mode = nil
			test_mode_wait_for_release = false
			last_active_time = emu.time()  -- Reset timer
			dprint("Test mode exited")
			return
		end
		
		-- Keep test mode running
		return
	end

	-- Early exit if screensaver is disabled (and not testing)
	if not settings.enabled then
		if screensaver_active then
			deactivate_screensaver()
		end
		return
	end

	local now = emu.time()
	local input_pressed = is_any_input_pressed()

	debug_counter = debug_counter + 1
	if settings.debug and debug_counter >= 60 then
		debug_counter = 0
		local elapsed = now - last_active_time
		dprint(string.format("Time: %.1fs, Elapsed: %.1fs, Input: %s, Active: %s",
			now, elapsed, tostring(input_pressed), tostring(screensaver_active)))
	end

	if input_pressed then
		last_active_time = now
		if screensaver_active then
			deactivate_screensaver()
		end
		return
	end

	if (not screensaver_active) and ((now - last_active_time) >= settings.timeout) then
		activate_screensaver()
	end
end

----------------------------------------------------------------------
-- TEST MODE SUPPORT
----------------------------------------------------------------------

function screensaver.start_test_mode(mode)
	dprint("Starting test mode: " .. mode)
	test_mode_active = true
	test_mode = mode
	test_mode_wait_for_release = true  -- Wait for button release first
	
	-- Immediately activate screensaver with the test mode
	local saved_mode = settings.mode
	settings.mode = mode
	activate_screensaver()
	settings.mode = saved_mode
end


----------------------------------------------------------------------
-- INIT / CLEANUP
----------------------------------------------------------------------

local function init_for_machine()
    dprint("Initializing for machine")
    
    SCREEN_ASPECT_RATIO = detect_screen_aspect_ratio()
    
    last_active_time   = emu.time()
    screensaver_active = false
    was_paused_by_us   = false
    last_anim_time     = nil
    debug_counter      = 0
    input_types_to_check  = nil
    host_codes_to_check   = nil

    if frame_subscription and frame_subscription.is_active then
        frame_subscription:unsubscribe()
    end
    if frame_done_subscription then
        frame_done_subscription()
        frame_done_subscription = nil
    end

    frame_subscription      = emu.add_machine_frame_notifier(process_frame)
    frame_done_subscription = emu.register_frame_done(draw_screensaver_overlay)

    dprint("Registered frame callbacks")
end

local function cleanup()
	dprint("Cleaning up")

	if screensaver_active and was_paused_by_us then
		emu.unpause()
		dprint("Machine resumed during cleanup")
	end

	if frame_subscription and frame_subscription.is_active then
		frame_subscription:unsubscribe()
	end
	if frame_done_subscription then
		frame_done_subscription()
	end

	frame_subscription      = nil
	frame_done_subscription = nil
	free_logo_texture()
	input_types_to_check  = nil
	host_codes_to_check   = nil
	
	-- Reset test mode
	test_mode_active = false
	test_mode = nil
	test_mode_wait_for_release = false
end

----------------------------------------------------------------------
-- MENU CALLBACKS
----------------------------------------------------------------------

local function menu_callback(index, event)
	return menu_handler:handle_event(index, event)
end

local function menu_populate()
	if not menu_handler then
		local status, msg = pcall(function () menu_handler = require('screensaver/screensaver_menu') end)
		if not status then
			emu.print_error(string.format('Error loading screensaver menu: %s', msg))
		end
		if menu_handler then
			menu_handler:init(settings, screensaver)  -- Pass screensaver module reference
		end
	end
	if menu_handler then
		return menu_handler:populate()
	else
		return { { 'Failed to load screensaver menu', '', 'off' } }
	end
end

----------------------------------------------------------------------
-- PLUGIN ENTRY POINTS
----------------------------------------------------------------------

function screensaver.startplugin()
    dprint("Plugin starting")
    
    -- Register callbacks
    reset_subscription = emu.add_machine_reset_notifier(function()
        -- Load settings when machine starts
        local persister = require('screensaver/screensaver_persist')
        settings = persister:load_settings()
        
        init_for_machine()
    end)
    
    stop_subscription  = emu.add_machine_stop_notifier(function()
        -- Save settings when machine stops
        local persister = require('screensaver/screensaver_persist')
        persister:save_settings(settings)
        
        cleanup()
    end)
    
    -- Register menu
    emu.register_menu(menu_callback, menu_populate, 'Screensaver')
    
    -- Load global settings now
    local persister = require('screensaver/screensaver_persist')
    settings = persister:load_settings()
    
    if manager.machine then
        init_for_machine()
    end
end

function screensaver.stopplugin()
    dprint("Plugin stopping")
    
    -- Save settings on plugin stop
    local persister = require('screensaver/screensaver_persist')
    persister:save_settings(settings)
    
    if frame_subscription and frame_subscription.is_active then
        frame_subscription:unsubscribe()
    end
    if frame_done_subscription then
        frame_done_subscription()
    end
    if reset_subscription and reset_subscription.is_active then
        reset_subscription:unsubscribe()
    end
    if stop_subscription and stop_subscription.is_active then
        stop_subscription:unsubscribe()
    end

    frame_subscription      = nil
    frame_done_subscription = nil
    reset_subscription      = nil
    stop_subscription       = nil
    menu_handler            = nil
    free_logo_texture()
end

return exports