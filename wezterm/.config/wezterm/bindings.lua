local wezterm = require("wezterm")
local act = wezterm.action
local openinhelix = require("open-helix")

local platform = {
	is_mac = wezterm.target_triple:find("darwin") ~= nil,
	is_win = wezterm.target_triple:find("windows") ~= nil,
	is_linux = wezterm.target_triple:find("linux") ~= nil,
}

local mod = {}
if platform.is_mac then
	mod.SUPER = "SUPER"
	mod.SUPER_REV = "SUPER|CTRL"
elseif platform.is_win or platform.is_linux then
	mod.SUPER = "SUPER" 
	mod.SUPER_REV = "SUPER|CTRL"
end

return function(choose_project)
local keys = {
	{ key = "q", mods = mod.SUPER, action = act.QuitApplication },

	{ key = "9", mods = mod.SUPER, action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }) },
	{ key = "n", mods = mod.SUPER, action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = mod.SUPER, action = act.SwitchWorkspaceRelative(-1) },
	{ key = "p", mods = "CTRL|SHIFT", action = act.ActivateCommandPalette },
	{ key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
	{ key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
	{ key = "x", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },

	{ key = ";", mods = mod.SUPER, action = choose_project },

	{ key = "Enter", mods = mod.SUPER, action = act.TogglePaneZoomState },

	{ key = "t", mods = mod.SUPER, action = act.SpawnTab("CurrentPaneDomain") },

	{ key = "/", mods = mod.SUPER, action = act.QuickSelect },
	{ key = "/", mods = mod.SUPER_REV, action = openinhelix.QuickSelect() },

	{ key = "d", mods = mod.SUPER, action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d", mods = "SHIFT|" .. mod.SUPER, action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "h", mods = mod.SUPER, action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = mod.SUPER, action = act.ActivatePaneDirection("Right") },
	{ key = "j", mods = mod.SUPER, action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = mod.SUPER, action = act.ActivatePaneDirection("Up") },

	{ key = "=", mods = mod.SUPER, action = act.IncreaseFontSize },
	{ key = "-", mods = mod.SUPER, action = act.DecreaseFontSize },
}

-- Tabs 1-8 (Alt+9 is the workspace launcher above).
for i = 1, 8 do
	table.insert(keys, { key = tostring(i), mods = mod.SUPER, action = act.ActivateTab(i - 1) })
end

return keys
end
