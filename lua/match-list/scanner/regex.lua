local M = {}

---@class MatchList.RegexScanner: MatchList.Scanner
---@field regex string The regex to scan for.
---@field groups string[] The names of the matched groups.
---@field postproc MatchList.PostProcFun A post-processing function.
local RegexScanner = {}
RegexScanner.__index = RegexScanner

---Creates a new regex scanner.
---@param regex string The regex to scan for.
---@param groups string[]? The names for the matched groups.
---@param postproc MatchList.PostProcFun? A post-processing function.
---@return MatchList.RegexScanner scanner The scanner.
function M.new(regex, groups, postproc)
	local scanner = {
		regex = regex,
		groups = groups or {},
		postproc = postproc or function(v) return v end,
	}

	setmetatable(scanner, RegexScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@return MatchList.Match[] matches The found matches.
function RegexScanner:scan(buffer, first, last)
	buffer = buffer or vim.api.nvim_get_current_buf()

	local matches = vim.fn.matchbufline(buffer, self.regex, first or 1, last or '$', { submatches = true })
	local result = {}

	for _, match in ipairs(matches) do
		local lines = vim.api.nvim_buf_get_lines(buffer, match.lnum - 1, match.lnum, false)

		if lines[1] then
			local data = {}

			for i, group in ipairs(self.groups) do
				data[group] = match.submatches[i]
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
					lnum = match.lnum,
					data = new_data
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
