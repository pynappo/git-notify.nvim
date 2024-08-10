local uv = vim.uv or vim.loop
local git_notify_augroup
local notify = vim.schedule_wrap(function(...)
	vim.notify(...)
end)

local default_config = {
	git_timeout = 1000 * 60 * 5, -- 5 minutes
	poll = {
		interval = 1000 * 60, -- 1 minute
		events = {}, -- unused but should be for autocmd events
		always_notify_for_details = false, -- send notifications on what's happening on every poll, mostly for debugging
	},
	---@type fun(git_info: table): string
	notify_formatter = function(git_info)
		local function auto_plural(count, plural, singular)
			return count > 1 and (count .. " " .. plural) or (count .. " " .. singular)
		end
		-- you can also use:
		-- git_info.branch_oid is the hash of the upstream branch
		-- git_info.git_dir is the directory where the git repo originates from
		local upstream_branch = git_info.upstream_branch
		local commits_ahead = git_info.commits_ahead
		local commits_behind = git_info.commits_behind
		if commits_ahead > 0 then
			if commits_behind > 0 then
				return ("You are %s ahead, %s behind of %s"):format(
					auto_plural(commits_ahead, "commits", "commit"),
					auto_plural(commits_behind, "commits", "commit"),
					upstream_branch
				)
			end
			return ("You are %s ahead of %s"):format(auto_plural(commits_ahead, "commits", "commit"), upstream_branch)
		elseif commits_behind > 0 then
			return ("You are %s behind of %s"):format(auto_plural(commits_behind, "commits", "commit"), upstream_branch)
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
	if not new_config or vim.tbl_isempty(new_config) then
		return
	end
	local updated_config = vim.tbl_deep_extend("force", gn.config, new_config or {})
	gn.config = updated_config
end

local function git_command(args)
	return {
		gn.config.git_executable or "git",
		"--no-pager",
		"--no-optional-locks",
		"--literal-pathspecs",
		"-c",
		"gc.auto=0",
		unpack(args),
	}
end

local function set_timeout(timeout, callback)
	local timer = uv.new_timer()
	timer:start(timeout, 0, function()
		timer:stop()
		timer:close()
		callback()
	end)
	return timer
end
function gn.update_remote_status(opts)
	opts = opts or {}
	opts.notify_for_details = opts.notify_for_details or gn.config.always_notify_for_details
	vim.system(git_command({ "rev-parse", "--absolute-git-dir" }), {}, function(git_dir_output)
		local git_dir = git_dir_output.stdout
		if git_dir_output.code ~= 0 or not git_dir then
			if opts.notify_for_details then
				notify("git_notify: no git repository found")
			end
			return
		end
		vim.system(git_command({ "fetch" }), {}, function(fetch_output)
			if fetch_output.code ~= 0 then
				notify("git-notify: git fetch failed", vim.log.levels.WARN)
				return
			end
			-- vim.schedule(function()
			-- 	vim.print(fetch_output)
			-- end)
			if opts.notify_for_details then
				if fetch_output == "" then
					notify("git-notify: no new data from remote")
				else
					notify("git-notify: fetched remote data")
				end
			end
			vim.system(git_command({ "status", "--porcelain=v2", "--branch" }), {}, function(branch_status_output)
				if branch_status_output.code ~= 0 then
					return
				end
				local lines = vim.split(branch_status_output.stdout, "\n", { plain = true })
				local has_upstream = #lines > 4 and lines[3]:sub(1, 1) == "#"
				if not has_upstream then
					if opts.notify_for_details then
						notify("git-notify: no upstream branch found", vim.log.levels.WARN)
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
				else
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

-- one-time setup
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.has("nvim-0.10.0") == 0 then
			vim.notify("git-notify currently only supports nvim 0.10 and up", vim.log.levels.ERROR)
			return
		end
		gn.configure(vim.g.git_notify_config)
		vim.api.nvim_create_user_command("GitNotifyCheck", function(ctx)
			gn.update_remote_status({ notify_for_details = true })
		end, {})
	end,
})

function gn.setup(user_config)
	git_notify_augroup = vim.api.nvim_create_augroup("git_notify", {
		clear = true,
	})

	gn.configure(user_config)
	vim.api.nvim_create_autocmd("User", {
		group = git_notify_augroup,
		pattern = "GitNotifySend",
		callback = function(ctx)
			vim.notify(gn.config.notify_formatter(ctx.data))
		end,
	})

	gn.start_polling(true)
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

function gn.start_polling(silent)
	if not silent then
		vim.notify("git-notify: Starting background polling")
	end
	gn.timer = gn.timer or vim.uv.new_timer()
	set_interval(gn.config.poll.interval, function()
		gn.update_remote_status({ notify_for_details = gn.config.always_notify_for_details })
	end, gn.timer)
end

function gn.stop_polling(silent)
	if not silent then
		vim.notify("git-notify: Stopping background polling")
	end
	clear_interval(gn.timer)
end

return gn
