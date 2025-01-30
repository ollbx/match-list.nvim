local M = {}

---@class MatchList.RegexScanner: MatchList.Scanner
---@field _regex string The regex to scan for.
---@field _groups string[] The names of the matched groups.
---@field _filter MatchList.FilterFun A filter function.
---@field _priority integer The match priority.
local RegexScanner = {}
RegexScanner.__index = RegexScanner

---Creates a new regex scanner.
---@param regex string The regex to scan for.
---@param groups string[]? The names for the matched groups.
---@param filter MatchList.FilterFun? A filter function.
---@param priority integer? The match priority.
---@return MatchList.RegexScanner scanner The scanner.
function M.new(regex, groups, filter, priority)
	local scanner = {
		_regex = regex,
		_groups = groups or {},
		_filter = filter or function(v) return v end,
		_priority = priority or 0,
	}

	setmetatable(scanner, RegexScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@param base_data MatchList.MatchData? Base match data to extend.
---@return MatchList.Match[] matches The found matches.
function RegexScanner:scan(buffer, first, last, base_data)
	buffer = buffer or vim.api.nvim_get_current_buf()

	local Util = require("match-list.util")
	local matches = vim.fn.matchbufline(buffer, self._regex, first or 1, last or '$', { submatches = true })
	local result = {}

	for _, match in ipairs(matches) do
		local lines = vim.api.nvim_buf_get_lines(buffer, match.lnum - 1, match.lnum, false)

		if lines[1] then
			local data = Util.unfold_groups(self._groups, match.submatches, base_data)
			local filter_data = self._filter(data)

			if filter_data then
				table.insert(result, {
					buffer = buffer,
					lines = 1,
					lnum = match.lnum,
					data = filter_data,
					priority = self._priority,
				})
			end
		end
	end

	return result
end

---Returns the number of lines matched.
function RegexScanner:get_lines()
	return 1
end

return M
