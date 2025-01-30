local M = {}

---@alias MatchList.EvalFun fun(line: string, data: MatchList.MatchData): MatchList.MatchData?

---@class MatchList.EvalScanner: MatchList.Scanner
---@field _eval MatchList.EvalFun The eval function.
---@field _filter MatchList.FilterFun A filter function.
---@field _priority integer The match priority.
local EvalScanner = {}
EvalScanner.__index = EvalScanner

---Creates a new lua eval scanner.
---@param eval MatchList.EvalFun The eval function.
---@param filter MatchList.FilterFun? A filter function.
---@param priority integer? The match priority.
---@return MatchList.EvalScanner scanner The scanner.
function M.new(eval, filter, priority)
	local scanner = {
		_eval = eval,
		_filter = filter or function(v) return v end,
		_priority = priority or 0,
	}

	setmetatable(scanner, EvalScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@param base_data MatchList.MatchData? Base match data to extend.
---@return MatchList.Match[] matches The found matches.
function EvalScanner:scan(buffer, first, last, base_data)
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local data = self._eval(line, vim.deepcopy(base_data or {}))

		if data then
			local filter_data = self._filter(data)

			if filter_data then
				table.insert(result, {
					buffer = buffer,
					lines = 1,
					lnum = lnum,
					data = filter_data,
					priority = self._priority,
				})
			end
		end
	end)

	return result
end

---Returns the number of lines matched.
function EvalScanner:get_lines()
	return 1
end

return M
