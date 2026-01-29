-- Screensaver settings persistence

local function settings_path()
	-- Use MAME’s cfg dir, keep it under plugins/screensaver
	if manager.machine then
		local homepath = manager.machine.options.entries.homepath:value():match('([^;]+)')
		return homepath .. '/plugins/screensaver'
	end

	-- Fallback: $CFG env if present
	local cfg = emu.subst_env('$CFG')
	if cfg and cfg ~= '$CFG' then
		return cfg .. '/plugins/screensaver'
	end

	-- Last resort: local dir
	return 'cfg/plugins/screensaver'
end

local function settings_filename()
	return 'screensaver.cfg'
end

local lib = {}

function lib:load_settings()
	local settings = {
		enabled = true,
		debug = false,
		mode = "bounce",
		timeout = 10.0,
		
		-- Bounce settings
		logo_speed_x = 0.25,
		logo_speed_y = 0.18,
		logo_scale = 0.25,
		
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
	
	local filename = settings_path() .. '/' .. settings_filename()
	local file = io.open(filename, 'r')
	if file then
		local json = require('json')
		local loaded = json.parse(file:read('a'))
		file:close()
		if loaded then
			-- Merge loaded settings with defaults
			for k, v in pairs(loaded) do
				settings[k] = v
			end
		else
			emu.print_verbose(string.format('Screensaver: error parsing settings file "%s" as JSON', filename))
		end
	end
	
	return settings
end

function lib:save_settings(settings)
	local path = settings_path()
	local stat = lfs.attributes(path)
	
	-- Make sure path exists and is a directory
	if stat and (stat.mode ~= 'directory') then
		emu.print_verbose(string.format('Screensaver: "%s" is not a directory, cannot save settings', path))
		return
	end
	
	if not stat then
		lfs.mkdir(path)
	end
	
	local filename = path .. '/' .. settings_filename()
	local json = require('json')
	local text = json.stringify(settings, { indent = true })
	local file = io.open(filename, 'w')
	
	if not file then
		emu.print_verbose(string.format('Screensaver: error opening file "%s" for writing', filename))
	else
		file:write(text)
		file:close()
	end
end

return lib