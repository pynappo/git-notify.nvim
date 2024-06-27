## Installation example for lazy.nvim:

```lua
{
  'pynappo/git-notify.nvim',
  -- opts/config is optional, require('git-notify').setup() is automatically called on startup
  -- most functionality is lazy-loaded so you shouldn't have to lazy-load.
}
```

## Configuration:

More docs may be added later, for now here's the default config:

```lua
local default_config = {
	git_timeout = 1000 * 60 * 5, -- 5 minutes
	poll = {
		interval = 1000 * 60, -- 1 minute
		events = {}, -- unused but should be for autocmd events
		always_notify_for_details = false, -- send notifications on what's happening on every poll, mostly for debugging
	},
	---@type fun(git_info: table): string
	notify_formatter = function(git_info)
		local function plural(count, multiple, singular)
			return count > 1 and (count .. " " .. multiple) or (count .. " " .. singular)
		end
		-- you can also use:
		-- git_info.branch_oid is the hash of the upstream branch
		-- git_info.git_dir is the directory where the git repo originates from
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
```

You can customize this by either setting `g:git_notify_config` or `vim.g.git_notify_config`
or by passing a table into `require('git-notify').setup()`.
