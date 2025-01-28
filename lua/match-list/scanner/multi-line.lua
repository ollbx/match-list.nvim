local M = {}

---@class MatchList.MultiLineScanner: MatchList.Scanner
---@field lines MatchList.Scanner[] Scanners for each consecutive line.
---@filed line_count integer The number of lines matched.
local MultiLineScanner = {}
MultiLineScanner.__index = MultiLineScanner

---Creates a new multi-line scanner.
---@param lines MatchList.Scanner[] Scanners for each consecutive line.
---@return MatchList.MultiLineScanner scanner The scanner.
function M.new(lines)
	local line_count = 0

	for _, scanner in ipairs(lines) do
		line_count = line_count + scanner:get_lines()
	end

	local scanner = {
		lines = lines,
		line_count = line_count,
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
	local matches = self.lines[1]:scan(buffer, first, last)

	-- If we only have one line, we are done here.
	if #self.lines <= 1 then
		return matches
	end

	local result = {}

	for _, match in ipairs(matches) do
		local lnum = match.lnum + 1
		local success = true

		for i=2,#self.lines do
			-- Note: multi-line matches only need their first line in-range.
			local next_matches = self.lines[i]:scan(buffer, lnum, lnum)
			local next_match = next_matches[1]

			if next_match then
				-- Extend the number of lines.
				match.lines = match.lines + next_match.lines
				lnum = lnum + next_match.lines

				-- Extend the captured data.
				match.data = vim.tbl_extend("force", match.data, next_match.data)
			else
				success = false
				break
			end
		end

		if success then
			table.insert(result, match)
		end
	end

	return result
end

---Returns the number of lines matched.
function MultiLineScanner:get_lines()
	return self.line_count
end

return M
