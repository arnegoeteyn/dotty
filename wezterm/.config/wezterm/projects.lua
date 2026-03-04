local wezterm = require("wezterm")
local M = {}
M.__index = M

M.New = function(dir)
	return setmetatable({
		dir = dir
	}, M)
end


function M:project_dirs()
	local projects = {}

	for _, dir in ipairs(wezterm.glob(self.dir .. "/*")) do
		table.insert(projects, { label = dir })
	end

	return projects
end

local function dev_workspace(cwd, label)
	local mux = wezterm.mux

	local _, helix_pane, _ = mux.spawn_window({
		workspace = label,
		cwd = label,
	})

	local lazygit_pane = helix_pane:split({
		direction = "Right",
		size = 0.5,
		cwd = cwd,
	})

	lazygit_pane:split({
		direction = "Bottom",
		size = 0.3,
		cwd = cwd,
	})

	helix_pane:send_text("hx .\n")
	lazygit_pane:send_text("lazygit\n")
end

function M:choose_project()
	return wezterm.action.InputSelector({
		title = "Projects",
		choices = self:project_dirs(),
		fuzzy = true,
		action = wezterm.action_callback(function(child_window, child_pane, _, label)
			if not label then
				return
			end

			local mux = wezterm.mux
			local existing_workspaces = mux.get_workspace_names()
			local workspace_exists = false
			for _, name in ipairs(existing_workspaces) do
				if name == label then
					workspace_exists = true
					break
				end
			end

			if not workspace_exists then
				dev_workspace(label, label)
			end

			child_window:perform_action(
				wezterm.action.SwitchToWorkspace({
					name = label,
				}),
				child_pane
			)
		end),
	})
end

return M
