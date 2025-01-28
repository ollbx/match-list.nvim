local M = {}

---The minimum update timeout between UI updates.
local UPDATE_TIMEOUT = 25

---@class MatchList.Tracker.Buffer Settings for a tracked buffer.
---@field group string[]? The match group to use or `nil` to use the global one.

---@class MatchList.Tracker.Hooks Hooks for the tracker.
---@field update fun(visible_matches: MatchList.Match[]) Called after update.

---@alias MatchList.Tracker.FilterFun fun(match: MatchList.Match): boolean A filter function for matches.
---@alias MatchList.Tracker.NotifyFun fun(match: MatchList.Match?, index: integer?, total: integer?) Notification function.
---
---@class MatchList.Tracker.GotoConfig
---@field filter MatchList.Tracker.FilterFun? Filter function for matches.
---@field notify MatchList.Tracker.NotifyFun? Notify function on navigation.
---@field focus boolean? `true` to switch to the window selected for showing the match.
---@field reuse boolean? `true` to reuse any open window that has the buffer already open.
---@field window integer? The window to open the match in (0 or `nil` for the current window).

---@alias MatchList.Tracker.HighlightFun fun(match: MatchList.Match): vim.api.keyset.set_extmark

---@class MatchList.Tracker.Config
---@field highlight MatchList.Tracker.HighlightFun? Hook for customizing highlights.

---@class MatchList.Tracker Tracks and highlights matches in buffers.
---@field _namespace integer The namespace used for extmarks.
---@field _config MatchList.Tracker.Config The tracker configuration.
---@field _buffers { integer: MatchList.Tracker.Buffer } The buffers tracked.
---@field _groups { string: MatchList.Scanner[] } The scanner groups available.
---@field _group string[]? The currently selected group.
---@field _matches MatchList.Match[]? The cached list of matches.
---@field _visible_matches MatchList.Match[] The list of visible matches.
---@field _scheduled boolean `true` if an update has been scheduled.
---@field _update_time integer The timestamp of the last update.
---@field _update_timer uv.uv_timer_t? The update timer ID.
---@field _current integer The currently selected index.
---@field _hooks MatchList.Tracker.Hooks Hook functions.
local Tracker = {}
Tracker.__index = Tracker

---Creates a new tracker.
---@return MatchList.Tracker tracker The tracker.
function M.new(config)
	local def_config = {
		highlight = function(match)
			local type = match.data["type"] or "hint"

			local highlight = {
				error = "DiagnosticSignError",
				warning = "DiagnosticSignWarn",
				info = "DiagnosticSignInfo",
			}

			return {
				sign_text = string.upper(string.sub(type, 1, 1)),
				sign_hl_group = highlight[type] or "DiagnosticSignHint",
				line_hl_group = highlight[type] or "DiagnosticSignHint",
			}
		end
	}

	config = vim.tbl_extend("force", def_config, config or {})

	local ui = {
		_namespace = vim.api.nvim_create_namespace(""),
		_config = config,
		_buffers = {},
		_groups = {},
		_group = nil,
		_matches = nil,
		_visible_matches = {},
		_scheduled = false,
		_update_time = vim.uv.now(),
		_update_timer = nil,
		_current = 0,
		_hooks = {
			update = function() end,
		}
	}

	vim.api.nvim_create_autocmd("WinScrolled", {
		--pattern = {}
		callback = function()
			local windows = vim.fn.getwininfo()
			local changes = vim.v.event

			-- Schedule an update if any of the scrolled windows show our buffer.
			for _, window in ipairs(windows) do
				if ui.buffers[window.bufnr] and changes[tostring(window.winid)] then
					ui:schedule_update()
					break
				end
			end
		end
	})

	setmetatable(ui, Tracker)
	return ui
end

---Updates the match groups.
---@param groups { string: MatchList.Scanner[] } The match groups.
function Tracker:setup_groups(groups)
	self._groups = groups
	self:schedule_update(true)
end

---Updates a specific match group.
---@param name string The name of the match group to set.
---@param group MatchList.Scanner[] The match group.
function Tracker:setup_group(name, group)
	self._groups[name] = group
	self:schedule_update(true)
end

---Returns the groups configured in the tracker.
---@return string[] groups The configured groups.
function Tracker:get_available_groups()
	local groups = {}

	for group, _ in pairs(self._groups) do
		table.insert(groups, group)
	end

	table.sort(groups, function(a, b)
		if a == "default" then
			-- Default is smaller than everything except for itself.
			return b ~= a
		else
			return a < b
		end
	end)

	return groups
end

---Selects the match groups to use for matching.
---@param group string|string[]|nil The name of the match groups to use or `nil` reset it.
---@param buffer integer? Restrict to buffer (0 for current buffer). `nil` to select globally.
function Tracker:set_group(group, buffer)
	if type(group) == "string" then
		group = { group }
	elseif type(group) ~= "table" and group ~= nil then
		error("Invalid group type.")
	end

	if buffer == nil then
		self._group = group
	else
		if buffer == 0 then
			buffer = vim.api.nvim_get_current_buf()
		end

		local config = self._buffers[buffer]

		if config then
			config.group = group
		end
	end

	self._matches = nil
	self:schedule_update(true)
end

---Returns the list of groups selected for a buffer.
---@param buffer integer? The buffer to query (`nil` or 0 for current buffer).
function Tracker:get_groups(buffer)
	if buffer == 0 or buffer == nil then
		buffer = vim.api.nvim_get_current_buf()
	end

	local config = self._buffers[buffer]

	if config then
		return (config.group or self._group) or { "default" }
	else
		return self._group or { "default" }
	end
end

---Attaches the tracker to the given buffer.
---@param buffer integer? The buffer to attach to. `nil` for the current buffer.
function Tracker:attach(buffer)
	if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
		buffer = vim.api.nvim_get_current_buf()
	end

	if not self._buffers[buffer] then
		self._buffers[buffer] = {}

		-- Schedule an update if our buffer changes.
		local ui = self

		vim.api.nvim_buf_attach(buffer, false, {
			on_reload = function()
				if ui._buffers[buffer] then
					ui:schedule_update()
					ui._matches = nil
				else
					-- detach
					return true
				end
			end,
			on_lines = function()
				if ui._buffers[buffer] then
					ui:schedule_update()
					ui._matches = nil
				else
					-- detach
					return true
				end
			end,
		})

		ui:schedule_update(true)
		ui._matches = nil
	end
end

---Detaches the tracker from the given buffer.
---@param buffer integer? The buffer to detach from. `nil` for the current buffer.
function Tracker:detach(buffer)
	if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
		buffer = vim.api.nvim_get_current_buf()
	end

	if self._buffers[buffer] then
		vim.api.nvim_buf_clear_namespace(buffer, self._namespace, 0, -1)
		self._buffers[buffer] = nil
		self:schedule_update(true)
	end
end

---Schedules an UI update to run in the near future.
---@param now boolean? Specify `true` to force an update as soon as possible.
function Tracker:schedule_update(now)
	-- If we do a forced update and one is scheduled, kill the scheduled update.
	if now and self._scheduled then
		self._update_timer:close()
		self._update_timer = nil
		self._scheduled = false
	end

	-- This will limit the amount of updates to only one update per `update_timeout`.
	if not self._scheduled then
		local ui = self
		self._scheduled = true

		local elapsed = vim.uv.now() - self._update_time
		local wait = UPDATE_TIMEOUT - math.min(elapsed, UPDATE_TIMEOUT)

		if now then
			wait = 0
		end

		self._update_timer = vim.defer_fn(function()
			ui:update()
			ui._scheduled = false
			ui._update_time = vim.uv.now()
		end, wait)
	end
end

---Removes any invalid buffers from the tracked buffer list.
function Tracker:check_buffers()
	local update = false

	for buffer, _ in pairs(self._buffers) do
		if not vim.api.nvim_buf_is_valid(buffer) then
			update = true
			break
		end
	end

	if update then
		local buffers = {}

		for buffer, config in pairs(self._buffers) do
			if vim.api.nvim_buf_is_valid(buffer) then
				buffers[buffer] = config
			end
		end

		self._buffers = buffers
	end
end

---Creates extmarks for matches in any part of the buffer that is currently
---visible through a window.
function Tracker:update()
	-- Remove old buffers.
	self:check_buffers()

	-- Clear all existing extmarks.
	for buffer, _ in pairs(self._buffers) do
		vim.api.nvim_buf_clear_namespace(buffer, self._namespace, 0, -1)
	end

	-- Collect all the windows that show our buffers.
	local windows = self:get_windows()

	-- Figure out the longest multi-line error we can match.
	local lines = 1

	for _, scanner in ipairs(self._groups) do
		lines = math.max(lines, scanner:get_lines())
	end

	self._visible_matches = {}

	for _, window in ipairs(windows) do
		-- Scan the visible area of the buffer for the given window.
		local first = math.max(1, window.topline - lines - 1)
		local last = window.botline
		local groups = self:get_groups(window.bufnr)

		for _, group in ipairs(groups) do
			local scanners = self._groups[group] or {}

			for _, scanner in ipairs(scanners) do
				local matches = scanner:scan(window.bufnr, first, last)

				for i, match in ipairs(matches) do
					local type = match.data["type"] or "hint"

					local mark_config = {
						end_row = match.lnum + match.lines - 2,
						hl_eol = true,
						hl_mode = "combine",
						sign_text = string.upper(string.sub(type, 1, 1)),
						sign_hl_group = "DiagnosticSignHint",
						line_hl_group = "DiagnosticSignHint",
					}

					-- Override highlight settings.
					mark_config = vim.tbl_extend("force", mark_config, self._config.highlight(match))

					if i == self._current then
						mark_config.line_hl_group = "Visual"
					end

					-- Create extmarks.
					vim.api.nvim_buf_set_extmark(window.bufnr, self._namespace, match.lnum - 1, 0, mark_config)

					table.insert(self._visible_matches, match)
				end
			end
		end
	end

	self._hooks.update(self._visible_matches)
end

---Returns all windows that currently contain one of the tracked buffers.
---@return [vim.fn.getwininfo.ret.item] windows The window list.
function Tracker:get_windows()
	-- Collect all the windows that show our buffer.
	local windows = {}

	for _, window in ipairs(vim.fn.getwininfo()) do
		if self._buffers[window.bufnr] then
			table.insert(windows, window)
		end
	end

	return windows
end

---Returns the currently selected match.
---@return MatchList.Match? The currently selected match or nil.
function Tracker:get_current()
	self:get_matches()
	return self._matches[self._current]
end

---Returns the index of the currently selected match.
---@return integer The currently selected index or 0 (if none is selected).
function Tracker:get_current_index()
	return self._current
end

---Returns all currently tracked matches.
---@return MatchList.Match[] matches The matches list.
function Tracker:get_matches()
	if not self._matches then
		self._matches = {}

		for buffer, _ in pairs(self._buffers) do
			local groups = self:get_groups(buffer)

			for _, group in ipairs(groups) do
				local scanners = self._groups[group] or {}

				for _, scanner in ipairs(scanners) do
					local matches = scanner:scan(buffer)

					for _, match in ipairs(matches) do
						table.insert(self._matches, match)
					end
				end
			end
		end

		table.sort(self._matches, function(a, b)
			if a.buffer ~= b.buffer then
				return a.buffer < b.buffer
			else
				return a.lnum < b.lnum
			end
		end)

		for i, match in ipairs(self._matches) do
			match.index = i
		end
	end

	return self._matches
end

---Returns all currently visible matches.
---@return MatchList.Match[] matches The matches list.
function Tracker:get_visible_matches()
	return self._visible_matches
end

---Default notification function.
local function default_notify(match, index, total)
	if match then
		vim.notify("[" .. index .. "/" .. total .. "]: " .. (match.data["message"] or "-"))
	else
		vim.notify("No more matches found")
	end
end

---Navigates to the specified match.
---@param match MatchList.Match? The match to scroll to.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
function Tracker:goto_match(match, config)
	local def_config = {
		focus = false,
		reuse = true,
		window = nil,
		notify = default_notify,
	}

	config = vim.tbl_extend("force", def_config, config or {})

	if match then
		local use_window = -1

		-- If window reuse is enabled, first try to find an open window for the buffer.
		if config.reuse then
			local windows = self:get_windows()

			for _, window in ipairs(windows) do
				if window.bufnr == match.buffer then
					use_window = window.winid
					break
				end
			end
		end

		if not vim.api.nvim_win_is_valid(use_window) then
			-- Use the window specified.
			if config.window then
				use_window = config.window
			end

			-- Fall back to the current window.
			if not vim.api.nvim_win_is_valid(use_window) then
				use_window = vim.api.nvim_get_current_win()
			end
		end

		vim.api.nvim_win_set_buf(use_window, match.buffer)
		vim.api.nvim_win_set_cursor(use_window, { match.lnum, 0 })

		if config.focus then
			vim.api.nvim_set_current_win(use_window)
		end

		self:schedule_update(true)

		if match.index ~= nil then
			self:get_matches()
			self._current = match.index
			config.notify(match, self._current, #self._matches)
		end
	else
		config.notify()
	end
end

---Moves the current item back or forward.
---@param amount integer The amount to skip ahead / backwards.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:skip(amount, config)
	local def_config = {
		filter = function() return true end,
	}

	config = vim.tbl_extend("force", def_config, config or {})
	self:get_matches()

	local new_index = self._current + amount

	while new_index >= 1 and new_index <= #self._matches do
		local match = self._matches[new_index]

		if config.filter(match) then
			self._current = new_index
			self:goto_match(match, config)
			return match
		else
			new_index = new_index + amount
		end
	end

	self:goto_match(nil, config )
end

---Moves to the next item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:next(config)
	return self:skip(1, config)
end

---Moves to the previous item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:prev(config)
	return self:skip(-1, config)
end

---Moves to the first item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:first(config)
	self:get_matches()
	self._current = 0
	return self:next(config)
end

---Moves to the last item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:last(config)
	self:get_matches()
	self._current = #self._matches + 1
	return self:prev(config)
end

---Resets the current item selection.
function Tracker:unselect()
	self._current = 0
	self:schedule_update(true)
end

---Sets the update hook function.
---the update hook is called after every ui update.
function Tracker:set_update_hook(fun)
	self._hooks.update = fun
end

return M
