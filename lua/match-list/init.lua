local M = {
	_tracker = nil,
	_commands = nil,
}

---@class MatchList.Config: MatchList.Tracker.Config
---@field groups MatchList.GroupConfig? The match group configuration.

---Configures the plugin.
---@param config MatchList.Config The plugin configuration.
function M.setup(config)
	local ok, err = pcall(function()
		local Scanner = require("match-list.scanner")
		local Tracker = require("match-list.tracker")

		local groups = Scanner.parse_groups(config.groups or {})

		M._tracker = Tracker.new(config)
		M._tracker:setup_groups(groups)
	end)

	if not ok then
		vim.notify(err --[[@as string]], vim.log.levels.ERROR)
	end

	-- Select group command.
	local function group(args, buffer)
		if #args == 0 then
			M.select_group(buffer)
		else
			M.set_group(args, buffer)
		end
	end

	local function make_filter(args)
		if #args > 1 then
			local types = {}

			for _, arg in ipairs(args) do
				types[arg] = true
			end

			return {
				filter = function(match)
					return types[match.data["type"]] ~= nil
				end
			}
		else
			return nil
		end
	end

	M._commands = {
		attach = function(args)
			if #args > 0 then
				M.attach(nil, args)
			else
				M.attach()
			end
		end,
		detach = function() M.detach() end,
		debug = function() M.debug() end,
		select = function() M.select() end,
		["goto"] = function() M.goto_below_cursor() end,
		next = function(args) M.next(make_filter(args)) end,
		prev = function(args) M.prev(make_filter(args)) end,
		first = function() M.first() end,
		last = function() M.last() end,
		unselect = function() M.unselect() end,
		group = function(args) group(args, nil) end,
		lgroup = function(args) group(args, 0) end,
		quickfix = function() M.send_to_quickfix() end,
	}

	local command = function(args)
		if #args.fargs == 0 then
			M.select()
		else
			local fun = M._commands[args.fargs[1]]
			local rest = {}

			for i=2,#args.fargs do
				table.insert(rest, args.fargs[i])
			end

			if fun then
				fun(rest)
			else
				vim.notify("Error: unrecognized command", vim.log.levels.ERROR)
			end
		end
	end

	vim.api.nvim_create_user_command("MatchList", command, {
		bar = true,
		nargs = "*",
		complete = function() return vim.tbl_keys(M._commands) end,
	})
end

---Returns the list of configured match groups.
---@return string[] groups The configured groups.
function M.get_available_groups()
	return M._tracker:get_available_groups()
end

---Selects the match groups to use for matching.
---@param group string|string[]|nil The name of the match groups to use or `nil` reset it.
---@param buffer integer? Restrict to buffer (0 for current buffer). `nil` to select globally.
function M.set_group(group, buffer)
	M._tracker:set_group(group, buffer)
end

---Selects the match group using the UI.
---@param buffer integer? Restrict to buffer (0 for current buffer). `nil` to select globally.
function M.select_group(buffer)
	local prompt = "Select global match group:"

	if buffer then
		prompt = "select match group (buffer " .. buffer .. "):"
	end

	vim.ui.select(M.get_available_groups(), {
		prompt = prompt,
	}, function(choice)
		if choice then
			M.set_group(choice, buffer)
		end
	end)
end

---Returns the list of groups selected for a buffer.
---@param buffer integer? The buffer to query (`nil` or 0 for current buffer).
function M.get_groups(buffer)
	return M._tracker:get_groups(buffer)
end

---Attaches the match list to the given buffer.
---@param buffer integer? The buffer to attach to. `nil` for the current buffer.
---@param group string|string[]|nil The name of the match groups to use or `nil` for default.
function M.attach(buffer, group)
	M._tracker:attach(buffer, group)
end

---Detaches the match list from the given buffer.
---@param buffer integer? The buffer to detach from. `nil` for the current buffer.
function M.detach(buffer)
	M._tracker:detach(buffer)
end

---Opens the match expression debugger.
function M.debug()
	require("match-list.debug").open()
end

---Runs the match benchmark suite.
function M.bench()
	require("match-list.bench").bench()
end

---Returns the currently selected match.
---@return MatchList.Match? The currently selected match or nil.
function M.get_current()
	return M._tracker:get_current()
end

---Returns the index of the currently selected match.
---@return integer The currently selected index or 0 (if none is selected).
function M.get_current_index()
	return M._tracker:get_current_index()
end

---Returns all currently tracked matches.
---@return MatchList.Match[] matches The matches list.
function M.get_matches()
	return M._tracker:get_matches()
end

---Returns all currently visible matches.
---@return MatchList.Match[] matches The matches list.
function M.get_visible_matches()
	return M._tracker:get_visible_matches()
end

---Default function used for formatting a match.
---@param match MatchList.Match The match to format.
local function default_format(match)
	if match.data["message"] then
		local s = ""

		if match.data["type"] then
			s = s .. string.upper(string.sub(match.data["type"], 1, 1)) .. " "
		end

		if match.data["file"] then
			s = s .. match.data["file"]

			if match.data["lnum"] then
				s = s .. ":" .. match.data["lnum"] .. " "
			end
		end

		return s .. match.data["message"]
	else
		return vim.inspect(match.data)
	end
end

---@alias MatchList.FormatFun fun(match: MatchList.Match): string

---@class MatchList.GotoConfig: MatchList.Tracker.GotoConfig
---@field format MatchList.FormatFun? Function used to format matches in the goto list.

---Opens a selection window for navigating to a specific match.
---@param config MatchList.GotoConfig? The navigation configaruation.
function M.select(config)
	local def_config = {
		format = default_format,
	}

	config = vim.tbl_extend("force", def_config, config or {})

	vim.ui.select(M._tracker:get_matches(), {
		prompt = "Goto match:",
		format_item = config.format,
	}, function(choice)
		if choice then
			M._tracker:goto_match(choice, config)
		end
	end)
end

---Finds the match item below the cursor and navigates to it.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function M.goto_below_cursor(config)
	return M._tracker:goto_below_cursor(config)
end

---Navigates to the specified match.
---@param match MatchList.Match The match to scroll to.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
function M.goto_match(match, config)
	M._tracker:goto_match(match, config)
end

---Moves to the next item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function M.next(config)
	return M._tracker:next(config)
end

---Moves to the previous item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function M.prev(config)
	return M._tracker:prev(config)
end

---Moves to the first item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function M.first(config)
	return M._tracker:first(config)
end

---Moves to the last item.
---@param config MatchList.Tracker.GotoConfig? The navigation config.
---@return MatchList.Match? match The match found or `nil`.
function M.last(config)
	return M._tracker:last(config)
end

---Resets the current item selection.
function M.unselect()
	M._tracker:unselect()
end

---@alias MatchList.QuickFixConvertFun fun(MatchList.Match): table

---@class MatchList.QuickFixConfig
---@field convert MatchList.QuickFixConvertFun? Conversion function.
---@field open boolean? `true` to open the quickfix.

---Sends the current list of matches to the quickfix.
---@param config MatchList.QuickFixConfig? Configuration options.
function M.send_to_quickfix(config)
	local def_config = {
		convert = function(match)
			return {
				filename = match.data["file"],
				lnum = match.data["lnum"],
				col = match.data["col"],
				text = match.data["message"],
				type = string.sub(match.data["type"] or "H", 1, 1),
			}
		end,
		open = true,
	}

	config = vim.tbl_extend("force", def_config, config or {})
	local items = {}

	for _, match in ipairs(M._tracker:get_matches()) do
		local item = config.convert(match)

		if item then
			table.insert(items, item)
		end
	end

	vim.fn.setqflist(items, ' ')

	if config.open then
		vim.cmd.copen()
	end
end

return M
