local M = {}

---@class MatchList.LpegScanner: MatchList.Scanner
---@field lpeg userdata The LPEG pattern to match.
---@field groups string[] The names of the matched groups.
---@field postproc MatchList.PostProcFun A post-processing function.
local LpegScanner = {}
LpegScanner.__index = LpegScanner

---Creates a new LPEG scanner.
---@param lpeg userdata The LPEG pattern to match.
---@param groups string[]? The names for the matched groups.
---@param postproc MatchList.PostProcFun? A post-processing function.
---@return MatchList.LpegScanner scanner The scanner.
function M.new(lpeg, groups, postproc)
	local scanner = {
		lpeg = lpeg,
		groups = groups or {},
		postproc = postproc or function(v) return v end,
	}

	setmetatable(scanner, LpegScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@return MatchList.Match[] matches The found matches.
function LpegScanner:scan(buffer, first, last)
	local lpeg = require("lpeg")
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local match = { lpeg.match(self.lpeg, line) }

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
function LpegScanner:get_lines()
	return 1
end

return M
