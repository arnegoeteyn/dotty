local wezterm = require("wezterm")
local act = wezterm.action
local projects = require("projects")
local appearance = require("appearance")

local config = wezterm.config_builder()

config.initial_cols = 120
config.initial_rows = 28
config.font_size = 18

if appearance.is_dark() then
	config.color_scheme = "Tokyo Night"
else
	config.color_scheme = "Tokyo Night Day"
end

config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

config.inactive_pane_hsb = {
	saturation = 0.3,
	brightness = 0.4,
}

config.native_macos_fullscreen_mode = true

config.keys = {
	{ key = "9", mods = "CMD", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
	{ key = "n", mods = "CMD", action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "CMD", action = act.SwitchWorkspaceRelative(-1) },

	{ key = ";", mods = "CMD", action = projects.choose_project() },

	{ key = "Enter", mods = "CMD", action = act.TogglePaneZoomState },

	{ key = "/", mods = "CMD", action = act.QuickSelect},

	{ key = "d", mods = "CMD", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d", mods = "SHIFT|CMD", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "h", mods = "CMD", action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = "CMD", action = act.ActivatePaneDirection("Right") },
	{ key = "j", mods = "CMD", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CMD", action = act.ActivatePaneDirection("Up") },
}

wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
	window:gui_window():toggle_fullscreen()
end)

local function segments_for_right_status(window)
	return {
		window:active_workspace(),
		wezterm.strftime("%a %b %-d %H:%M"),
		wezterm.hostname(),
	}
end

wezterm.on("update-status", function(window, _)
	local SOLID_LEFT_ARROW = utf8.char(0xe0b2)
	local segments = segments_for_right_status(window)

	local color_scheme = window:effective_config().resolved_palette
	local bg = wezterm.color.parse(color_scheme.background)
	local fg = color_scheme.foreground

	local gradient_to, gradient_from = bg
	if appearance.is_dark() then
		gradient_from = gradient_to:lighten(0.2)
	else
		gradient_from = gradient_to:darken(0.2)
	end

	local gradient = wezterm.color.gradient(
		{
			orientation = "Horizontal",
			colors = { gradient_from, gradient_to },
		},
		#segments -- only gives us as many colours as we have segments.
	)

	local elements = {}

	for i, seg in ipairs(segments) do
		local is_first = i == 1

		if is_first then
			table.insert(elements, { Background = { Color = "none" } })
		end
		table.insert(elements, { Foreground = { Color = gradient[i] } })
		table.insert(elements, { Text = SOLID_LEFT_ARROW })

		table.insert(elements, { Foreground = { Color = fg } })
		table.insert(elements, { Background = { Color = gradient[i] } })
		table.insert(elements, { Text = " " .. seg .. " " })
	end

	window:set_right_status(wezterm.format(elements))
end)

return config
