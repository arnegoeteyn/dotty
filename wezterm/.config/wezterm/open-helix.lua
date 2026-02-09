local M = {}

local wezterm = require("wezterm")
local act = wezterm.action

function string.startswith(str, prefix)
	return string.sub(str, 1, string.len(prefix)) == prefix
end

local function basename(s)
	return string.gsub(s, "(.*[/\\])(.*)", "%2")
end

local function filter(tbl, predicate)
	local result = {}
	for _, v in ipairs(tbl) do
		if predicate(v) then
			table.insert(result, v)
		end
	end
	return result
end

local function hx_pane(window)
	local success, stdout = wezterm.run_child_process({ "/opt/homebrew/bin/wezterm", "cli", "list", "--format=json" })

	if success then
		local json = wezterm.json_parse(stdout)
		if not json then
			return
		end

		local workspace_panes = filter(json, function(p)
			return p.workspace == window:active_workspace()
		end)

		for _, p in ipairs(workspace_panes) do
			local pane = wezterm.mux.get_pane(p.pane_id)
			if pane then
				local process = basename(pane:get_foreground_process_name())
				if process == "hx" then
					return pane
				end
			end
		end
	end
end

function M.open_with_hx(window, filename)
	local target_pane = hx_pane(window)

	if target_pane then
		local command = ":open " .. filename .. "\r\n"
		wezterm.log_info(command)
		local action = act.SendString(command)
		window:perform_action(action, target_pane)
		target_pane:activate()
	end
end

M.filters = {}

function M.QuickSelect()
	local patterns = {
		"[^\\s]+\\.go:\\d+",
		"[^\\s]+\\.go:\\d+:\\d+",
	}

	return act.QuickSelectArgs({
		label = "open file",
		patterns = patterns,
		action = wezterm.action_callback(function(window, pane)
			local selection = window:get_selection_text_for_pane(pane)
			return M.open_with_hx(window, selection )
		end),
	})
end

return M
