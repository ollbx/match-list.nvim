local M = {}

---@class MatchList.MatchScanner: MatchList.Scanner
---@field _pattern string The match string to scan for.
local MatchScanner = {}
MatchScanner.__index = MatchScanner

---Creates a new lua pattern scanner.
---@param pattern string The match string to scan for.
---@param groups string[]? The names for the matched groups.
---@return MatchList.MatchScanner scanner The scanner.
function M.new(pattern, groups)
	local scanner = {
		_pattern = pattern,
		_groups = groups or {},
		_filter = function(v) return v end,
		_priority = 0,
	}

	setmetatable(scanner, MatchScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer The buffer to scan.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@param base_data MatchList.MatchData? Base match data to extend.
---@return MatchList.Match[] matches The found matches.
function MatchScanner:scan(buffer, first, last, base_data)
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local match = { string.match(line, self._pattern) }

		if match[1] ~= nil then
			local data = Util.unfold_groups(self._groups, match, base_data)
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
function MatchScanner:get_lines()
	return 1
end

return M
