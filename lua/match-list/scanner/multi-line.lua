local M = {}

---@class MatchList.MultiLineScanner: MatchList.Scanner
---@field _lines MatchList.Scanner[] Scanners for each consecutive line.
---@field _line_count integer The number of lines matched.
---@field _filter MatchList.FilterFun A filter function.
local MultiLineScanner = {}
MultiLineScanner.__index = MultiLineScanner

---Creates a new multi-line scanner.
---@param lines MatchList.Scanner[] Scanners for each consecutive line.
---@param filter MatchList.FilterFun? A filter function.
---@return MatchList.MultiLineScanner scanner The scanner.
function M.new(lines, filter)
	local line_count = 0

	for _, scanner in ipairs(lines) do
		line_count = line_count + scanner:get_lines()
	end

	local scanner = {
		_lines = lines,
		_line_count = line_count,
		_filter = filter or function(v) return v end,
	}

	if #lines < 1 then
		error("Multi-line scanner needs at least one line.")
	end

	setmetatable(scanner, MultiLineScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---
---The range is used for the first line of the match. Consecutive lines can
---overrun the specified range.
---
---@param buffer integer The buffer to scan.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@return MatchList.Match[] matches The found matches.
function MultiLineScanner:scan(buffer, first, last)
	-- Scan with the first scanner.
	local matches = self._lines[1]:scan(buffer, first, last)

	-- If we only have one line, we are done here.
	if #self._lines <= 1 then
		return matches
	end

	local result = {}

	for _, match in ipairs(matches) do
		local lnum = match.lnum + 1
		local success = true

		for i=2,#self._lines do
			-- Note: multi-line matches only need their first line in-range.
			local next_matches = self._lines[i]:scan(buffer, lnum, lnum, match.data)
			local next_match = next_matches[1]

			if next_match then
				-- Extend the number of lines.
				match.lines = match.lines + next_match.lines
				lnum = lnum + next_match.lines

				-- Take over the extended match data.
				match.data = next_match.data
			else
				success = false
				break
			end
		end

		if success then
			local filter_data = self._filter(match.data)

			if filter_data then
				match.data = filter_data
				table.insert(result, match)
			end
		end
	end

	return result
end

---Returns the number of lines matched.
function MultiLineScanner:get_lines()
	return self._line_count
end

return M
