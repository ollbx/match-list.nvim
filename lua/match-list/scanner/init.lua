-- Scanners will scan a buffer range or a single line for matches of a pattern.
-- They can match single or multiple lines.

---@class MatchList.Scanner
---@field scan fun(self: MatchList.Scanner, buffer: integer, first: integer?, last: integer?, base_data: MatchList.MatchData?): [MatchList.Match]
---@field get_lines fun(): integer
---@field _groups string[] The names of the matched groups.
---@field _filter MatchList.FilterFun A filter function.
---@field _priority integer The match priority.

---@alias MatchList.MatchData { string: string }

---@class MatchList.Match
---@field index integer? The index of the match.
---@field buffer integer The buffer that the match was on.
---@field lines integer The number of lines matched.
---@field lnum integer The line number of the match.
---@field data MatchList.MatchData The captured data of the match.
---@field priority integer The match priority.

---@alias MatchList.FilterFun fun(data: MatchList.MatchData): MatchList.MatchData?

local M = {
	new_eval = require("match-list.scanner.eval").new,
	new_regex = require("match-list.scanner.regex").new,
	new_match = require("match-list.scanner.match").new,
	new_lpeg = require("match-list.scanner.lpeg").new,
	new_multi_line = require("match-list.scanner.multi-line").new,
}

---@alias MatchList.MatchFun fun(string): MatchList.MatchData?
---@alias MatchList.ScannerConfig MatchList.MatchFun|string|table
---@alias MatchList.GroupConfig { string: MatchList.ScannerConfig[] }

---Parses a scanner configuration.
---@param config MatchList.ScannerConfig The scanner config to parse.
function M.parse(config)
	if type(config) == "function" then
		return M.new_eval(config)
	elseif type(config) == "string" then
		return M.new_regex(config)
	elseif type(config) == "table" then
		local scanner
		local group_index

		if config["regex"] then
			scanner = M.new_regex(config["regex"])
			group_index = 1
		elseif config["match"] then
			scanner = M.new_match(config["match"])
			group_index = 1
		elseif config["lpeg"] then
			scanner = M.new_lpeg(config["lpeg"])
			group_index = 1
		elseif config["eval"] then
			scanner = M.new_eval(config["eval"])
			group_index = 1
		elseif type(config[1]) == "string" then
			scanner = M.new_regex(config[1])
			group_index = 2
		elseif type(config[1]) == "function" then
			scanner = M.new_eval(config[1])
			group_index = 2
		elseif type(config[1]) == "table" then
			local lines = {}

			for _, line in ipairs(config) do
				table.insert(lines, M.parse(line))
			end

			scanner = M.new_multi_line(lines)
		end

		if not scanner then
			error("Invalid scanner config: " .. vim.inspect(config))
		end

		if group_index then
			scanner._groups = (config["groups"] or config[group_index]) or {}

			if type(scanner._groups) ~= "table" then
				error("Invalid groups. Expected table, found: " .. vim.inspect(scanner._groups))
			end
		end

		scanner._priority = config["priority"] or 0
		scanner._filter = config["filter"] or function(v) return v end

		if type(scanner._priority) ~= "number" then
			error("Invalid priority. Expected number, found: " .. vim.inspect(scanner._priority))
		end

		if type(scanner._filter) ~= "function" then
			error("Invalid filter. Expected function, found: " .. vim.inspect(scanner._priority))
		end

		return scanner
	else
		error("Invalid scanner config: " .. vim.inspect(config))
	end
end

---Parses a scanner group configuration.
---@param config MatchList.GroupConfig The group config to parse.
function M.parse_groups(config)
	local groups = {}

	for group, scanner_configs in pairs(config) do
		local scanners = {}

		for _, scanner_config in ipairs(scanner_configs) do
			table.insert(scanners, M.parse(scanner_config))
		end

		groups[group] = scanners
	end

	return groups
end

return M
