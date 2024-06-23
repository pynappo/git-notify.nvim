local uv = vim.uv or vim.loop
local g = vim.g

local git_notify_augroup = vim.api.nvim_create_augroup("git_notify", {
	clear = true,
})
local default_config = {
	poll = {
		interval = 1000 * 60, -- 1 minute
		events = {},
		only_notify_if_remote_updated = true,
	},
	notify_string_formatter = function() end,
}
local gn = {
	config = default_config,
}
function gn.configure(new_config)
	local updated_config = vim.tbl_deep_extend("force", gn.config, new_config)
	gn.config = updated_config
end

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

local BRANCH_UPSTREAM_LENGTH = 1 + #"# branch.upstream "
local function plural(count, multiple, singular)
	return count > 1 and (count .. " " .. multiple) or (count .. " " .. singular)
end
local notify = vim.schedule_wrap(function(...)
	vim.notify(...)
end)
function gn.default_notify_formatter(git_info)
	local upstream_branch = git_info.upstream_branch
	local commits_ahead = git_info.commits_ahead
	local commits_behind = git_info.commits_behind
	if commits_ahead > 0 then
		return "You are " .. plural(commits_ahead, "commits", "commit") .. " ahead of " .. upstream_branch
	elseif commits_behind > 0 then
		return "You are " .. plural(commits_behind, "commits", "commit") .. " behind " .. upstream_branch
	else
		return "You are up-to-date with " .. upstream_branch
	end
end
function gn.update_remote_status(opts)
	opts = opts or {}
	vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, {}, function(output)
		if output.code ~= 0 then
			return
		end

		if opts.log then
			notify("fetching remote data")
		end

		vim.system({ "git", "remote", "update" }, {}, function()
			vim.system({ "git", "status", "--porcelain=v2", "--branch" }, {}, function(branch_status_output)
				if branch_status_output.code ~= 0 then
					return
				end
				local lines = vim.split(branch_status_output.stdout, "\n", { plain = true })
				local has_upstream = #lines > 4 and lines[3]:sub(1, 1) == "#"
				if not has_upstream then
					if opts.log then
						notify("git_notify: no upstream found", vim.log.levels.WARN)
					end
					return
				end

				local upstream_branch = lines[3]:sub(BRANCH_UPSTREAM_LENGTH)
				local _, _, commits_ahead, commits_behind = lines[4]:find("%+(%d+) %-(%d+)")
				commits_ahead = tonumber(commits_ahead)
				commits_behind = tonumber(commits_behind)
				local git_info = {
					upstream_branch = upstream_branch,
					commits_ahead = commits_ahead,
					commits_behind = commits_behind,
				}
				vim.g.git_notify_info = git_info
				vim.schedule(function()
					vim.api.nvim_exec_autocmds("User", {
						pattern = "GitNotifyUpdate",
						data = git_info,
					})
				end)
			end)
		end)
	end)
end

gn.configure(vim.g.git_notify_config or {})
function gn.setup(user_config)
	user_config = user_config or {}
	gn.configure(user_config)
	vim.api.nvim_create_autocmd("User", {
		pattern = "GitNotifyUpdate",
		callback = function(ctx)
			vim.notify(gn.default_notify_formatter(ctx.data))
		end,
	})
	vim.api.nvim_create_user_command("GitNotifyCheck", function(ctx)
		gn.update_remote_status({ log = true })
	end, {})
	gn.start()
end

function gn.start()
	gn.timer = gn.timer or vim.uv.new_timer()
	set_interval(gn.config.poll.interval, gn.update_remote_status, gn.timer)
end

function gn.stop()
	clear_interval(gn.timer)
end

return gn
