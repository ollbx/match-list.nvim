local M = {}

---@class MatchList.MatchScanner: MatchList.Scanner
---@field pattern string The match string to scan for.
---@field groups string[] The names of the matched groups.
---@field postproc MatchList.PostProcFun A post-processing function.
local MatchScanner = {}
MatchScanner.__index = MatchScanner

---Creates a new lua pattern scanner.
---@param pattern string The match string to scan for.
---@param groups string[]? The names for the matched groups.
---@param postproc MatchList.PostProcFun? A post-processing function.
---@return MatchList.MatchScanner scanner The scanner.
function M.new(pattern, groups, postproc)
	local scanner = {
		pattern = pattern,
		groups = groups or {},
		postproc = postproc or function(v) return v end,
	}

	setmetatable(scanner, MatchScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer The buffer to scan.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@return MatchList.Match[] matches The found matches.
function MatchScanner:scan(buffer, first, last)
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local match = { string.match(line, self.pattern) }

		if match[1] ~= nil then
			local data = {}

			for i, group in ipairs(self.groups) do
				data[group] = match[i]
			end

			for key, value in pairs(self.groups) do
				if type(key) ~= "number" then
					data[key] = value
				end
			end

			local new_data = self.postproc(data)

			if new_data then
				table.insert(result, {
					buffer = buffer,
					lines = 1,
					lnum = lnum,
					data = new_data
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
