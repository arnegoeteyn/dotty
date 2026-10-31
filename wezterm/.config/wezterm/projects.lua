local wezterm = require("wezterm")
local module = {}

local mux = wezterm.mux
local killworkspace = require("workspace-kill")

local function repos_file()
	local ok, stdout = wezterm.run_child_process({ "realpath", wezterm.config_file })
	if not ok then
		return nil
	end
	-- <dotty>/wezterm/.config/wezterm/wezterm.lua -> <dotty>/repos.yaml
	local dotty = stdout:gsub("%s+$", ""):match("^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$")
	return dotty and (dotty .. "/repos.yaml")
end

local function expand_home(path)
	return (path:gsub("^~", wezterm.home_dir))
end

-- Minimal parser for repos.yaml (root + repos.<name>.{url,path});
-- this wezterm build has no wezterm.serde.
local function parse_repos(content)
	local cfg, current = { repos = {} }, nil
	for line in content:gmatch("[^\n]+") do
		line = line:gsub("%s+#.*$", ""):gsub("^#.*$", "")
		local indent, key, value = line:match("^(%s*)([%w_%-]+):%s*(.-)%s*$")
		if key then
			value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			if #indent == 0 then
				current = nil
				if key == "root" then
					cfg.root = value
				end
			elseif #indent == 2 then
				current = {}
				cfg.repos[key] = current
			elseif current and value ~= "" then
				current[key] = value
			end
		end
	end
	return cfg
end

local function projects()
	local file = repos_file()
	local f = file and io.open(file, "r")
	if not f then
		wezterm.log_error("projects: cannot open repos.yaml (" .. tostring(file) .. ")")
		return {}
	end
	-- The picker is built at config load, so reload when repos.yaml changes.
	wezterm.add_to_config_reload_watch_list(file)
	local content = f:read("*a")
	f:close()

	local cfg = parse_repos(content)

	local root = expand_home(cfg.root or "")
	local list = {}
	for name, repo in pairs(cfg.repos or {}) do
		local path = repo.path and expand_home(repo.path) or (root .. "/" .. name)
		table.insert(list, { name = name, path = path, layout = repo.layout })
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Waits for Enter so the sandbox only starts when actually wanted.
local function sandbox_prompt(label)
	return "read -P 'Press Enter to start sandbox " .. label .. "... ' answer; and asbx run " .. label .. "\n"
end

local function dev_workspace(cwd, label)
	local _, helix_pane, window = mux.spawn_window({
		workspace = label,
		cwd = cwd,
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

	local _, test_pane = window:spawn_tab({ cwd = cwd })

	local opencode_pane = test_pane:split({
		direction = "Right",
		size = 0.5,
		cwd = cwd,
	})

	opencode_pane:send_text(sandbox_prompt(label))

	helix_pane:activate({})
end

local function worktree_workspace(cwd, label)
	local _, helix_pane, window = mux.spawn_window({
		workspace = label,
		cwd = cwd,
	})

	local lazygit_pane = helix_pane:split({
		direction = "Right",
		size = 0.5,
		cwd = cwd,
	})

	lazygit_pane:split({
		direction = "Bottom",
		size = 0.3,
		cwd = cwd .. "/main",
	})

	helix_pane:send_text("hx main\n")
	lazygit_pane:send_text("lazygit -p main\n")

	local _, test_pane = window:spawn_tab({ cwd = cwd .. "/main" })

	local opencode_pane = test_pane:split({
		direction = "Right",
		size = 0.5,
		cwd = cwd .. "/clanker",
	})

	opencode_pane:send_text(sandbox_prompt(label))

	helix_pane:activate({})
end

local layouts = {
	dev = dev_workspace,
	worktree = worktree_workspace,
}

-- opts.close_startup: after a pick, kill the workspace the picker was opened
-- from (the empty one wezterm creates on launch).
function module.choose_project(opts)
	opts = opts or {}
	local choices, by_name = {}, {}
	for _, p in ipairs(projects()) do
		by_name[p.name] = p
		table.insert(choices, { id = p.path, label = p.name })
	end

	return wezterm.action.InputSelector({
		title = "Projects",
		choices = choices,
		fuzzy = true,
		action = wezterm.action_callback(function(child_window, child_pane, id, label)
			if not id then
				return
			end

			local modname = label
			local previous = child_window:active_workspace()
			local existing_workspaces = mux.get_workspace_names()
			local workspace_exists = false
			for _, name in ipairs(existing_workspaces) do
				if name == modname then
					workspace_exists = true
					break
				end
			end

			if not workspace_exists then
				local layout = by_name[modname].layout or "dev"
				local spawn = layouts[layout]
				if not spawn then
					wezterm.log_error("projects: unknown layout '" .. layout .. "' for " .. modname .. ", using dev")
					spawn = dev_workspace
				end
				spawn(id, modname)
			end

			child_window:perform_action(
				wezterm.action.SwitchToWorkspace({
					name = modname,
				}),
				child_pane
			)

			if opts.close_startup and previous ~= modname then
				killworkspace.kill_workspace(previous)
			end
		end),
	})
end

return module
