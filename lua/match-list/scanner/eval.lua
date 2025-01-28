local M = {}

---@alias MatchList.EvalFun fun(string): MatchList.MatchData?

---@class MatchList.EvalScanner: MatchList.Scanner
---@field eval MatchList.EvalFun The eval function.
local EvalScanner = {}
EvalScanner.__index = EvalScanner

---Creates a new lua eval scanner.
---@param eval MatchList.EvalFun The eval function.
---@return MatchList.EvalScanner scanner The scanner.
function M.new(eval)
	local scanner = {
		eval = eval,
	}

	setmetatable(scanner, EvalScanner)
	return scanner
end

---Scans a range of the given buffer.
---Row indices start at row 1. The range is end-inclusive.
---@param buffer integer|nil The buffer to scan. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@return MatchList.Match[] matches The found matches.
function EvalScanner:scan(buffer, first, last)
	local Util = require("match-list.util")
	local result = {}

	buffer = buffer or vim.api.nvim_get_current_buf()

	Util.iterate_lines(buffer, first, last, nil, function(line, lnum)
		local data = self.eval(line)

		if data then
			if type(data) == "boolean" then
				data = {}
			end

			if type(data) == "table" then
				table.insert(result, {
					buffer = buffer,
					lines = 1,
					lnum = lnum,
					data = data
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
