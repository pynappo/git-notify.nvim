local uv = vim.uv or vim.loop
local git_notify_augroup = vim.api.nvim_create_augroup("git_notify", {
	clear = true,
})
local notify = vim.schedule_wrap(function(...)
	vim.notify(...)
end)

local default_config = {
	poll = {
		interval = 1000 * 60, -- 1 minute
		events = {},
		always_notify = true,
	},
	notify_formatter = function(git_info)
		local function plural(count, multiple, singular)
			return count > 1 and (count .. " " .. multiple) or (count .. " " .. singular)
		end
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
	end,
}
local gn = {
	cache = {},
	get_default_config = function()
		return vim.deepcopy(default_config)
	end,
}
gn.config = gn.get_default_config()

function gn.configure(new_config)
	if not new_config then
		return
	end
	local updated_config = vim.tbl_deep_extend("force", gn.config, new_config or {})
	gn.config = updated_config
end

function gn.update_remote_status(opts)
	opts = opts or {}
	opts.notify_for_details = opts.notify_for_details or gn.config.always_notify_for_details
	vim.system({ "git", "rev-parse", "--absolute-git-dir" }, {}, function(git_dir_output)
		local git_dir = git_dir_output.stdout
		if git_dir_output.code ~= 0 or not git_dir then
			if opts.notify_for_details then
				notify("git_notify: no git repository found")
			end
			return
		end
		vim.system({ "git", "fetch" }, {}, function()
			if opts.notify_for_details then
				notify("git-notify: fetched remote data")
			end
			vim.system({ "git", "status", "--porcelain=v2", "--branch" }, {}, function(branch_status_output)
				if branch_status_output.code ~= 0 then
					return
				end
				local lines = vim.split(branch_status_output.stdout, "\n", { plain = true })
				local has_upstream = #lines > 4 and lines[3]:sub(1, 1) == "#"
				if not has_upstream then
					if opts.notify_for_details then
						notify("git-notify: no upstream found", vim.log.levels.WARN)
					end
					return
				end

				local branch_oid = lines[1]:sub(#"# branch.oid " + 1)
				local upstream_branch = lines[3]:sub(1 + #"# branch.upstream ")
				local _, _, commits_ahead, commits_behind = lines[4]:find("%+(%d+) %-(%d+)")

				local git_info = {
					git_dir = git_dir,
					branch_oid = branch_oid,
					upstream_branch = upstream_branch,
					commits_ahead = tonumber(commits_ahead),
					commits_behind = tonumber(commits_behind),
				}

				local cache_entry = vim.tbl_get(gn.cache, git_dir, branch_oid)
				local differs_from_cache = false
				if not cache_entry then
					gn.cache[git_dir] = {}
					gn.cache[git_dir][branch_oid] = git_info
					cache_entry = git_info
					differs_from_cache = true
				end
				if not differs_from_cache then
					for k, v in pairs(cache_entry) do
						if v ~= git_info[k] then
							differs_from_cache = true
							gn.cache[git_dir][branch_oid] = git_info
							break
						end
					end
				end

				local should_notify = differs_from_cache or opts.notify_for_details
				if should_notify then
					vim.g.git_notify_info = git_info
					vim.schedule(function()
						vim.api.nvim_exec_autocmds("User", {
							pattern = "GitNotifySend",
							data = git_info,
						})
					end)
				end
			end)
		end)
	end)
end

gn.configure(vim.g.git_notify_config)
local GIT_VERSION_LENGTH = #"git version "
function gn.setup(user_config)
	if vim.fn.has("nvim-0.10.0") == 0 then
		vim.notify("git-notify currently only supports nvim 0.10 and up", vim.log.levels.ERROR)
		return
	end
	vim.system({ "git", "--version" }, {}, function(version_output)
		if version_output.code ~= 0 then
			notify("git-notify: could not execute git --version", vim.log.levels.ERROR)
			return
		end
		gn.git_version = vim.version.parse(version_output.stdout:sub(GIT_VERSION_LENGTH))
		if vim.version.lt(gn.git_version, { 2, 13, 0 }) then
			notify("git-notify: expected git v2.13.0, got " .. gn.git_version, vim.log.levels.ERROR)
		end
	end)
	gn.configure(user_config)

	vim.api.nvim_create_autocmd("User", {
		group = git_notify_augroup,
		pattern = "GitNotifySend",
		callback = function(ctx)
			vim.notify(gn.config.notify_formatter(ctx.data))
		end,
	})

	vim.api.nvim_create_user_command("GitNotifyCheck", function(ctx)
		gn.update_remote_status({ notify_for_details = true })
	end, {})
	gn.start_polling()
end

local function set_interval(interval, callback, timer)
	timer = timer or uv.new_timer()
	timer:start(0, interval, function()
		callback()
	end)
	return timer
end

local function clear_interval(timer)
	timer:stop()
	timer:close()
end

function gn.start_polling()
	gn.timer = gn.timer or vim.uv.new_timer()
	set_interval(gn.config.poll.interval, function()
		gn.update_remote_status({ always_notify = gn.config.always_notify_for_details })
	end, gn.timer)
end

function gn.stop_polling()
	clear_interval(gn.timer)
end

return gn
