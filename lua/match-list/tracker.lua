local M = {}

---The minimum update timeout between UI updates.
local UPDATE_TIMEOUT = 25

---@class MatchList.Tracker.Buffer Settings for a tracked buffer.
---@field group string[]? The match group to use or `nil` to use the global one.

---@class MatchList.Tracker.Hooks Hooks for the tracker.
---@field update fun(visible_matches: MatchList.Match[]) Called after update.

---@alias MatchList.Tracker.FilterFun fun(match: MatchList.Match): boolean? A filter function for matches.
---@alias MatchList.Tracker.NotifyFun fun(match: MatchList.Match?, index: integer?, total: integer?) Notification function.
---@alias MatchList.Tracker.LoadFun fun(match: MatchList.Match): boolean? Function to load a file for a match.
---@alias MatchList.Tracker.OpenFun fun(match: MatchList.Match): integer? Function to open a window for a match.
---
---@class MatchList.Tracker.GotoConfig
---@field filter MatchList.Tracker.FilterFun? Filter function for matches.
---@field notify MatchList.Tracker.NotifyFun? Notify function on navigation.
---@field file_window integer? The window to open the target file in. `nil` to not open the target file, `0` to open in the file window, `id` to open it in a specific window.
---@field file_open MatchList.Tracker.OpenFun? If the file window is not available, this is called to open or select window for the target file.
---@field file_load MatchList.Tracker.LoadFun? Function used to open a buffer for the given match in the current window.
---@field match_window integer? The window to open the match in. `nil` to not open the match, `0` to open in any existing window, `id` to open it in a specific window.
---@field match_open MatchList.Tracker.OpenFun? If the match buffer is not currently open, this is called to open or select a window for it.
---@field focus string Specifies where the focus should end up. `nil` to leave the focus unchanged, `file` to focus on the opened file, `match` to focus on the match.

---@alias MatchList.Tracker.HighlightFun fun(match: MatchList.Match): vim.api.keyset.set_extmark
---@alias MatchList.Tracker.AttachFun fun(buffer: integer, tracker: MatchList.Tracker)
---@alias MatchList.Tracker.DetachFun fun(buffer: integer, tracker: MatchList.Tracker)

---@class MatchList.Tracker.Config
---@field highlight MatchList.Tracker.HighlightFun? Hook for customizing highlights.
---@field attach MatchList.Tracker.AttachFun? Function to run when attaching.
---@field detach MatchList.Tracker.DetachFun? Function to run when detaching.
---@field split string "horizontal", "vertical", "h" or "v".

---@class MatchList.Tracker Tracks and highlights matches in buffers.
---@field _namespace integer The namespace used for extmarks.
---@field _config MatchList.Tracker.Config The tracker configuration.
---@field _buffers { integer: MatchList.Tracker.Buffer } The buffers tracked.
---@field _groups { string: MatchList.Scanner[] } The scanner groups available.
---@field _group string[]? The currently selected group.
---@field _matches MatchList.Match[]? The cached list of matches.
---@field _visible_matches MatchList.Match[] The list of visible matches.
---@field _scheduled boolean `true` if an update has been scheduled.
---@field _file_window integer The cached file window or -1.
---@field _update_time integer The timestamp of the last update.
---@field _update_timer uv.uv_timer_t? The update timer ID.
---@field _current integer The currently selected index.
---@field _current_match MatchList.Match? The current match.
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
		end,
		attach = function(buffer, tracker)
			vim.keymap.set("n", "<cr>", function()
				tracker:goto_below_cursor()
			end, { buffer = buffer })
		end,
		detach = function(buffer)
			vim.keymap.del("n", "<cr>", {
				buffer = buffer,
			})
		end,
	}

	config = vim.tbl_extend("force", def_config, config or {})

	local tracker = {
		_namespace = vim.api.nvim_create_namespace(""),
		_config = config,
		_buffers = {},
		_groups = {},
		_group = nil,
		_matches = nil,
		_visible_matches = {},
		_scheduled = false,
		_file_window = -1,
		_update_time = vim.uv.now(),
		_update_timer = nil,
		_current = 0,
		_current_match = nil,
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
				if tracker._buffers[window.bufnr] and changes[tostring(window.winid)] then
					tracker:schedule_update()
					break
				end
			end
		end
	})

	setmetatable(tracker, Tracker)
	return tracker
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

---Changes the file window used for opening files.
---@param window integer The window ID to use.
---@param force boolean? `true` to force setting the window.
function Tracker:set_file_window(window, force)
	if force or not vim.api.nvim_win_is_valid(self._file_window) then
		self._file_window = window
	end
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
---@param group string|string[]|nil The name of the match groups to use or `nil` for default.
function Tracker:attach(buffer, group)
	if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
		buffer = vim.api.nvim_get_current_buf()
	end

	if not self._buffers[buffer] then
		self._buffers[buffer] = {}

		-- Schedule an update if our buffer changes.
		local tracker = self

		vim.api.nvim_buf_attach(buffer, false, {
			on_reload = function()
				if tracker._buffers[buffer] then
					tracker:schedule_update()
					tracker._matches = nil
				else
					-- detach
					return true
				end
			end,
			on_lines = function()
				if tracker._buffers[buffer] then
					tracker:schedule_update()
					tracker._matches = nil
				else
					-- detach
					return true
				end
			end,
		})

		self._config.attach(buffer, self)
	end

	if group then
		self:set_group(group, buffer)
	end

	self:schedule_update(true)
	self._matches = nil
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

		self._config.detach(buffer, self)
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
		local tracker = self
		self._scheduled = true

		local elapsed = vim.uv.now() - self._update_time
		local wait = UPDATE_TIMEOUT - math.min(elapsed, UPDATE_TIMEOUT)

		if now then
			wait = 0
		end

		self._update_timer = vim.defer_fn(function()
			tracker:update()
			tracker._scheduled = false
			tracker._update_time = vim.uv.now()
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

	local found = {}

	for _, window in ipairs(windows) do
		-- Scan the visible area of the buffer for the given window.
		local first = math.max(1, window.topline - lines - 1)
		local last = window.botline
		local groups = self:get_groups(window.bufnr)

		for _, group in ipairs(groups) do
			local scanners = self._groups[group] or {}

			for _, scanner in ipairs(scanners) do
				local matches = scanner:scan(window.bufnr, first, last)

				for _, match in ipairs(matches) do
					local key = match.buffer .. "-" .. match.lnum

					if not found[key] or match.priority > found[key].priority then
						found[key] = match
					end
				end
			end
		end
	end

	self._visible_matches = {}

	for _, match in pairs(found) do
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

		if self._current_match and self._current_match.lnum == match.lnum and self._current_match.buffer == match.buffer then
			mark_config.line_hl_group = "Visual"
		end

		-- Create extmarks.
		vim.api.nvim_buf_set_extmark(match.buffer, self._namespace, match.lnum - 1, 0, mark_config)

		table.insert(self._visible_matches, match)
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
	return self._current_match
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
		local found = {}

		for buffer, _ in pairs(self._buffers) do
			local groups = self:get_groups(buffer)

			for _, group in ipairs(groups) do
				local scanners = self._groups[group] or {}

				for _, scanner in ipairs(scanners) do
					local matches = scanner:scan(buffer)

					for _, match in ipairs(matches) do
						local key = match.buffer .. "-" .. match.lnum

						if not found[key] or match.priority > found[key].priority then
							found[key] = match
						end

					end
				end
			end
		end

		self._matches = {}

		for _, match in pairs(found) do
			table.insert(self._matches, match)
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

		-- Update the current match entry.
		if self._current ~= nil then
			self._current_match = self._matches[self._current]
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
		vim.notify("No more matches found", vim.log.levels.WARN)
	end
end

local split_file = {
	horizontal = "above",
	vertical = "right",
	h = "above",
	v = "right",
}

local split_match = {
	horizontal = "below",
	vertical = "left",
	h = "below",
	v = "left",
}

---Navigates to the specified match.
---@param match MatchList.Match? The match to scroll to.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
function Tracker:goto_match(match, config)
	local def_config = {
		notify = default_notify,
		file_window = 0,
		file_open = function()
			return vim.api.nvim_open_win(0, false, {
				split = split_file[self._config.split] or "above",
			})
		end,
		file_load = function(file_match)
			local file = file_match.data["file"]

			if vim.fn.filereadable(file) == 1 then
				local ok = pcall(vim.cmd, "buffer " .. vim.fn.fnameescape(file))
				if not ok then
					vim.cmd("edit " .. vim.fn.fnameescape(file))
				end
				return true
			end
		end,
		match_window = 0,
		match_open = function()
			return vim.api.nvim_open_win(0, false, {
				split = split_match[self._config.split] or "below",
			})
		end,
		focus = "file",
	}

	config = vim.tbl_extend("force", def_config, config or {})

	if match then
		local file_window = config.file_window
		local match_window = config.match_window

		if file_window == 0 or not vim.api.nvim_win_is_valid(file_window) then
			-- Select the current window as the file window.
			file_window = vim.api.nvim_get_current_win()
		end

		-- Disable the file window, if we have no file information.
		if not match.data["file"] then
			file_window = nil
		end

		if match_window == 0 then
			-- Try to find an open match window that is not the file window.
			for _, window in ipairs(self:get_windows()) do
				if window.bufnr == match.buffer then
					match_window = window.winid

					if match_window ~= file_window then
						break
					end
				end
			end
		end

		if match_window == file_window then
			-- Select a different file window on conflict.
			if vim.api.nvim_win_is_valid(self._file_window) and self._file_window ~= match_window then
				-- Fall back to the previously used window.
				file_window = self._file_window
			else
				-- Open a new window for the file.
				file_window = config.file_open(match)
			end
		end

		local old_win = vim.api.nvim_get_current_win()

		if file_window and vim.api.nvim_win_is_valid(file_window) then
			-- Remember the file window.
			self._file_window = file_window
			vim.api.nvim_set_current_win(file_window)

			if config.file_load(match) then
				local lnum = tonumber(match.data["lnum"])
				local col = (tonumber(match.data["col"]) or 1) - 1

				if lnum then
					vim.api.nvim_win_set_cursor(0, { lnum, col })
				end
			else
				vim.notify("Could not open file " .. match.data["file"])
			end
		end

		if match_window and vim.api.nvim_win_is_valid(match_window) then
			-- No match window found?
			if match_window == 0 then
				match_window = config.match_open(match)
			end

			if vim.api.nvim_win_is_valid(match_window) then
				vim.api.nvim_win_set_buf(match_window, match.buffer)
				vim.api.nvim_win_set_cursor(match_window, { match.lnum, 0 })
			end
		end

		-- Set the new focus.
		if config.focus == "file" then
			if file_window and vim.api.nvim_win_is_valid(file_window) then
				vim.api.nvim_set_current_win(file_window)
			end
		elseif config.focus == "match" then
			if match_window and vim.api.nvim_win_is_valid(match_window) then
				vim.api.nvim_set_current_win(match_window)
			end
		else
			vim.api.nvim_set_current_win(old_win)
		end

		if match.index ~= nil then
			self:get_matches()
			self._current = match.index
			self._current_match = match
			config.notify(match, self._current, #self._matches)
		end

		self:schedule_update(true)
	else
		config.notify()
	end
end

---Finds the match item below the cursor and navigates to it.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:goto_below_cursor(config)
	local buffer = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum = cursor[1]

	self:get_matches()

	-- Use the current window as the match window.
	config = config or {}
	config.match_window = vim.api.nvim_get_current_win()

	-- Try to find a matching item.
	for _, match in ipairs(self._matches) do
		local first = match.lnum
		local last = match.lnum + match.lines - 1

		if match.buffer == buffer and lnum >= first and lnum <= last then
			self:goto_match(match, config)
			return match
		end
	end
end

---Moves the current item back or forward.
---@param amount integer The amount to skip ahead / backwards.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function Tracker:skip(amount, config)
	local def_config = {
		notify = default_notify,
		filter = function() return true end,
	}

	config = vim.tbl_extend("force", def_config, config or {})
	self:get_matches()

	local new_index = self._current + amount

	while new_index >= 1 and new_index <= #self._matches do
		local match = self._matches[new_index]

		if config.filter(match) then
			self._current = new_index
			self._current_match = match
			self:goto_match(match, config)
			return match
		else
			new_index = new_index + amount
		end
	end

	-- Try to go to the current item again.
	if self._current_match then
		local match = self._current_match

		if config.filter(match) then
			-- Go to the current item again, but don't notify.
			local goto_config = vim.tbl_extend("force", config, {
				notify = function() end
			})

			self:goto_match(match, goto_config)

			-- Show the "no more matches" notification.
			config.notify()
			return match
		end
	end

	self:goto_match(nil, config)
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
	self._current_match = nil
	self:schedule_update(true)
end

---Sets the update hook function.
---the update hook is called after every ui update.
function Tracker:set_update_hook(fun)
	self._hooks.update = fun
end

return M
