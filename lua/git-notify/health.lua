local M = {}

local gn = require("git-notify")
M.check = function()
	vim.health.start("git-notify")

	-- check config types
	local config_ok, err_msg = pcall(vim.validate, {
		git_executable = {
			gn.config.git_executable,
			{ "string", "nil" },
		},
		git_timeout = {
			gn.config.git_timeout,
			"number",
		},
		notify_formatter = {
			gn.config.notify_formatter,
			function(formatter)
				local test_git_info = {
					branch_oid = "06a5e32e613de60ece049c0cecca2661417de267",
					commits_ahead = 0,
					commits_behind = 0,
					git_dir = "/home/dle/code/nvim/git-notify.nvim/.git\n",
					upstream_branch = "origin/main",
				}
				if type(formatter) ~= "function" then
					return false, "`notify-formatter` is not a function"
				end
				if type(formatter(test_git_info)) ~= "string" then
					return false, "`notify-formatter` function does not return a string"
				end
				return true
			end,
		},
		["poll.interval"] = {
			gn.config.poll.interval,
			"number",
		},
		["poll.events"] = {
			gn.config.poll.events,
			"table",
		},
		["poll.always_notify"] = {
			gn.config.poll.always_notify,
			"boolean",
		},
	})
	if config_ok then
		vim.health.ok("config types are correct")
	else
		vim.health.error("at least one config parameter is of the wrong type.", err_msg)
	end

	-- check git version
	local git_version_output = vim.system({ "git", "--version" }, {}, function(version_output) end):wait()
	if git_version_output.code ~= 0 then
		vim.health.error(
			"git-notify: could not execute git --version",
			"check if git is executable (on $PATH or set `git_executable`)"
		)
		return
	else
		vim.health.ok("git is executable")
	end
	local git_version = vim.version.parse(git_version_output.stdout:sub(#"git version "))
	if vim.version.lt(git_version or {}, { 2, 13, 0 }) then
		vim.health.error(
			"git version < 2.13, got " .. gn.git_version.major .. "." .. gn.git_version.minor,
			"try updating your git version if possible, or file an issue on the github repo for support for older git versions"
		)
	else
		vim.health.ok("git version >= 2.13")
	end
end

return M
