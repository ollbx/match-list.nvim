local M = {}

---@class MatchList.LpegScanner: MatchList.Scanner
---@field _lpeg userdata The LPEG pattern to match.
---@field _groups string[] The names of the matched groups.
local LpegScanner = {}
LpegScanner.__index = LpegScanner

---Creates a new LPEG scanner.
---@param lpeg userdata The LPEG pattern to match.
---@param groups string[]? The names for the matched groups.
---@return MatchList.LpegScanner scanner The scanner.
function M.new(lpeg, groups)
	local scanner = {
		_lpeg = lpeg,
		_groups = groups or {},
		_filter = function(v) return v end,
		_priority = 0,
	}

	setmetatable(scanner, LpegScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@param base_data MatchList.MatchData? Base match data to extend.
---@return MatchList.Match[] matches The found matches.
function LpegScanner:scan(buffer, first, last, base_data)
	local lpeg = require("lpeg")
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local match = { lpeg.match(self._lpeg, line) }

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
function LpegScanner:get_lines()
	return 1
end

return M
