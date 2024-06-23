local uv = vim.uv or vim.loop
local g = vim.g

local git_notify = {}
local default_config = {
	poll_interval = 1000 * 60, -- 1 minute
	poll_events = {},
}

local function set_interval(interval, callback, timer)
	local timer = timer or uv.new_timer()
	timer:start(0, interval, function()
		callback()
	end)
	return timer
end

local function clear_interval(timer)
	timer:stop()
	timer:close()
end

function git_notify.update_remote_status(opts, command_context)
	opts = opts or {}
	command_context = command_context or {}
	vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, {}, function(output)
		if output.code ~= 0 then
			return
		end

		if opts.log then
			vim.schedule(function()
				vim.print(output)
				vim.notify("fetching remote data")
			end)
		end

		vim.system({ "git", "remote", "update" }, {}, function()
			vim.system({ "git", "status", "--porcelain=v2", "--branch" }, {}, function(branch_status_output)
				if branch_status_output.code ~= 0 then
					return
				end
				local lines = vim.split(branch_status_output.stdout, "\n", { plain = true })
				local has_upstream = lines[3]:sub(1, 1) == "#"
				if not has_upstream then
					return
				end

				local _, _, commits_behind = lines[4]:find("%+(%d) %-(%d+)")
				vim.schedule(function()
					vim.notify("You are " .. commits_behind .. " commits behind the remote branch")
				end)
			end)
		end)
	end)
end

function git_notify.configure(opts)
	local config = opts and vim.tbl_deep_extend("force", g.tabnames_config, opts) or g.tabnames_config
	g.tabnames_config = config
	return g.tabnames_config
end

function git_notify.setup(user_config)
	git_notify.configure(user_config)
	git_notify.start()
	vim.api.nvim_create_user_command("GitNotifyCheck", function(ctx)
		git_notify.update_remote_status({ log = true }, ctx)
	end, {})
end

function git_notify.start()
	git_notify.timer = git_notify.timer or vim.uv.new_timer()
	set_interval(git_notify.config.poll_interval, git_notify.update_remote_status, git_notify.timer)
end

function git_notify.stop()
	clear_interval(git_notify.timer)
end

return git_notify
