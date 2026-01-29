-- Screensaver configuration menu

local MENU_TYPES = {
	MAIN = 0,
	BOUNCE = 1,
	STARFIELD = 2,
	MYSTIFY = 3,
	MATRIX = 4,
	FIREWORKS = 5,
	PLASMA = 6
}

local menu_stack
local settings
local screensaver_module

-- Track "Done" button indices for each submenu
local bounce_done
local starfield_done
local mystify_done
local matrix_done
local fireworks_done
local plasma_done

-- Helper to format boolean
local function bool_to_str(val)
	return val and "On" or "Off"
end

-- Helper to cycle through mode options
local modes = { "bounce", "starfield", "mystify", "matrix", "fireworks", "plasma", "random" }
local function cycle_mode(current, direction)
	for i, mode in ipairs(modes) do
		if mode == current then
			local new_index = i + direction
			if new_index < 1 then new_index = #modes end
			if new_index > #modes then new_index = 1 end
			return modes[new_index]
		end
	end
	return current
end

-- Helper to cycle through plasma palettes
local palettes = { "rainbow", "fire", "ocean", "matrix" }
local function cycle_palette(current, direction)
	for i, pal in ipairs(palettes) do
		if pal == current then
			local new_index = i + direction
			if new_index < 1 then new_index = #palettes end
			if new_index > #palettes then new_index = 1 end
			return palettes[new_index]
		end
	end
	return current
end

-- Main menu handlers
local function handle_main(index, event)
	if event == 'select' then
		if index == 3 then -- Enabled toggle
			settings.enabled = not settings.enabled
			return true
		elseif index == 4 then -- Debug toggle
			settings.debug = not settings.debug
			return true
		elseif index == 9 then -- Bounce settings
			table.insert(menu_stack, MENU_TYPES.BOUNCE)
			return true
		elseif index == 10 then -- Starfield settings
			table.insert(menu_stack, MENU_TYPES.STARFIELD)
			return true
		elseif index == 11 then -- Mystify settings
			table.insert(menu_stack, MENU_TYPES.MYSTIFY)
			return true
		elseif index == 12 then -- Matrix settings
			table.insert(menu_stack, MENU_TYPES.MATRIX)
			return true
		elseif index == 13 then -- Fireworks settings
			table.insert(menu_stack, MENU_TYPES.FIREWORKS)
			return true
		elseif index == 14 then -- Plasma settings
			table.insert(menu_stack, MENU_TYPES.PLASMA)
			return true
		end
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 1 or -1
		if index == 6 then -- Mode
			settings.mode = cycle_mode(settings.mode, direction)
			return true
		elseif index == 7 then -- Timeout (minutes, UI-facing)
			-- Internal storage is seconds; convert to minutes for editing
			local minutes = settings.timeout / 60.0

			local STEP_MINUTES = 1   -- 1 minute steps (60 seconds)
			local MIN_MINUTES  = 1   -- 15 minute minimum

			minutes = minutes + direction * STEP_MINUTES
			if minutes < MIN_MINUTES then
				minutes = MIN_MINUTES
			end

			settings.timeout = minutes * 60.0
			return true
		end
	end
	return false
end

local function populate_main()
	return {
		{ 'Screensaver Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Enabled', bool_to_str(settings.enabled), '' },
		{ 'Debug Mode', bool_to_str(settings.debug), '' },
		{ '---', '', '' },
		{ 'Mode', settings.mode, 'lr' },
		-- Display timeout in minutes with one decimal
		{ 'Timeout (minutes)', string.format('%.1f', settings.timeout / 60.0), 'lr' },
		{ '---', '', '' },
		{ 'Bounce Settings', '', '' },
		{ 'Starfield Settings', '', '' },
		{ 'Mystify Settings', '', '' },
		{ 'Matrix Settings', '', '' },
		{ 'Fireworks Settings', '', '' },
		{ 'Plasma Settings', '', '' }
	}
end

-- Bounce menu
local function handle_bounce(index, event)
	if (event == 'back') or ((event == 'select') and (index == bounce_done)) then
		bounce_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == bounce_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('bounce')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 0.05 or -0.05
		if index == 3 then -- Logo Scale
			settings.logo_scale = math.max(0.1, math.min(0.75, settings.logo_scale + direction))
			return true
		elseif index == 4 then -- Horizontal Speed
			settings.logo_speed_x = math.max(0.05, math.min(2.0, settings.logo_speed_x + direction))
			return true
		elseif index == 5 then -- Vertical Speed
			settings.logo_speed_y = math.max(0.05, math.min(2.0, settings.logo_speed_y + direction))
			return true
		end
	end
	return false
end

local function populate_bounce()
	local items = {
		{ 'Bounce Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Logo Scale', string.format('%.2f', settings.logo_scale), 'lr' },
		{ 'Horizontal Speed', string.format('%.2f', settings.logo_speed_x), 'lr' },
		{ 'Vertical Speed', string.format('%.2f', settings.logo_speed_y), 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	bounce_done = #items
	return items
end

-- Starfield menu
local function handle_starfield(index, event)
	if (event == 'back') or ((event == 'select') and (index == starfield_done)) then
		starfield_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == starfield_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('starfield')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 1 or -1
		if index == 3 then
			settings.star_count = math.max(50, math.min(500, settings.star_count + direction * 10))
			return true
		elseif index == 4 then
			settings.star_speed = math.max(0.1, math.min(2.0, settings.star_speed + direction * 0.1))
			return true
		end
	end
	return false
end

local function populate_starfield()
	local items = {
		{ 'Starfield Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Star Count', string.format('%d', settings.star_count), 'lr' },
		{ 'Speed', string.format('%.1f', settings.star_speed), 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	starfield_done = #items
	return items
end

-- Mystify menu
local function handle_mystify(index, event)
	if (event == 'back') or ((event == 'select') and (index == mystify_done)) then
		mystify_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == mystify_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('mystify')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 1 or -1
		if index == 3 then
			settings.mystify_polygons = math.max(1, math.min(5, settings.mystify_polygons + direction))
			return true
		elseif index == 4 then
			settings.mystify_points = math.max(3, math.min(10, settings.mystify_points + direction))
			return true
		elseif index == 5 then
			settings.mystify_speed = math.max(0.1, math.min(1.0, settings.mystify_speed + direction * 0.05))
			return true
		end
	end
	return false
end

local function populate_mystify()
	local items = {
		{ 'Mystify Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Polygons', string.format('%d', settings.mystify_polygons), 'lr' },
		{ 'Points per Polygon', string.format('%d', settings.mystify_points), 'lr' },
		{ 'Speed', string.format('%.2f', settings.mystify_speed), 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	mystify_done = #items
	return items
end

-- Matrix menu
local function handle_matrix(index, event)
	if (event == 'back') or ((event == 'select') and (index == matrix_done)) then
		matrix_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == matrix_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('matrix')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 1 or -1
		if index == 3 then
			settings.matrix_columns = math.max(40, math.min(200, settings.matrix_columns + direction * 10))
			return true
		elseif index == 4 then
			settings.matrix_speed = math.max(0.1, math.min(2.0, settings.matrix_speed + direction * 0.1))
			return true
		end
	end
	return false
end

local function populate_matrix()
	local items = {
		{ 'Matrix Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Columns', string.format('%d', settings.matrix_columns), 'lr' },
		{ 'Speed', string.format('%.1f', settings.matrix_speed), 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	matrix_done = #items
	return items
end

-- Fireworks menu
local function handle_fireworks(index, event)
	if (event == 'back') or ((event == 'select') and (index == fireworks_done)) then
		fireworks_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == fireworks_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('fireworks')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 0.1 or -0.1
		if index == 3 then
			settings.fireworks_launch_rate = math.max(0.1, math.min(2.0, settings.fireworks_launch_rate + direction))
			return true
		end
	end
	return false
end

local function populate_fireworks()
	local items = {
		{ 'Fireworks Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Launch Rate', string.format('%.1f', settings.fireworks_launch_rate), 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	fireworks_done = #items
	return items
end

-- Plasma menu
local function handle_plasma(index, event)
	if (event == 'back') or ((event == 'select') and (index == plasma_done)) then
		plasma_done = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == plasma_done - 1) then
		-- Test button (one before Done)
		if screensaver_module and screensaver_module.start_test_mode then
			screensaver_module.start_test_mode('plasma')
		end
		return true
	elseif event == 'left' or event == 'right' then
		local direction = (event == 'right') and 1 or -1
		if index == 3 then
			settings.plasma_speed = math.max(0.5, math.min(5.0, settings.plasma_speed + direction * 0.5))
			return true
		elseif index == 4 then
			settings.plasma_palette = cycle_palette(settings.plasma_palette, direction)
			return true
		end
	end
	return false
end

local function populate_plasma()
	local items = {
		{ 'Plasma Settings', '', 'off' },
		{ '---', '', '' },
		{ 'Speed', string.format('%.1f', settings.plasma_speed), 'lr' },
		{ 'Palette', settings.plasma_palette, 'lr' },
		{ '---', '', '' },
		{ 'Test', '', '' },
		{ 'Done', '', '' }
	}
	plasma_done = #items
	return items
end

-- Entry points
local lib = {}

function lib:init(config, saver_module)
	menu_stack = { MENU_TYPES.MAIN }
	settings = config
	screensaver_module = saver_module
end

function lib:handle_event(index, event)
	local current = menu_stack[#menu_stack]
	if current == MENU_TYPES.MAIN then
		return handle_main(index, event)
	elseif current == MENU_TYPES.BOUNCE then
		return handle_bounce(index, event)
	elseif current == MENU_TYPES.STARFIELD then
		return handle_starfield(index, event)
	elseif current == MENU_TYPES.MYSTIFY then
		return handle_mystify(index, event)
	elseif current == MENU_TYPES.MATRIX then
		return handle_matrix(index, event)
	elseif current == MENU_TYPES.FIREWORKS then
		return handle_fireworks(index, event)
	elseif current == MENU_TYPES.PLASMA then
		return handle_plasma(index, event)
	end
	return false
end

function lib:populate()
	local current = menu_stack[#menu_stack]
	if current == MENU_TYPES.MAIN then
		return populate_main()
	elseif current == MENU_TYPES.BOUNCE then
		return populate_bounce()
	elseif current == MENU_TYPES.STARFIELD then
		return populate_starfield()
	elseif current == MENU_TYPES.MYSTIFY then
		return populate_mystify()
	elseif current == MENU_TYPES.MATRIX then
		return populate_matrix()
	elseif current == MENU_TYPES.FIREWORKS then
		return populate_fireworks()
	elseif current == MENU_TYPES.PLASMA then
		return populate_plasma()
	end
	return {{ 'Error', '', 'off' }}
end

return lib
