-- Scanners will scan a buffer range or a single line for matches of a pattern.
-- They can match single or multiple lines.

---@class MatchList.Scanner
---@field scan fun(self: MatchList.Scanner, buffer: integer, first: integer?, last: integer?, base_data: MatchList.MatchData?): [MatchList.Match]
---@field get_lines fun(): integer

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

local function check_groups(groups)
	if type(groups) ~= "table" then
		error("Expected table for groups. Found: " .. vim.inspect(groups))
	end
end

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
	elseif config["regex"] then
		local groups = (config["groups"] or config[1]) or {}
		check_groups(groups)
		return M.new_regex(config["regex"], groups, config["filter"], config["priority"])
	elseif config["match"] then
		local groups = (config["groups"] or config[1]) or {}
		check_groups(groups)
		return M.new_match(config["match"], groups, config["filter"], config["priority"])
	elseif config["lpeg"] then
		local groups = (config["groups"] or config[1]) or {}
		check_groups(groups)
		return M.new_lpeg(config["lpeg"], groups, config["filter"], config["priority"])
	elseif config["eval"] then
		return M.new_eval(config["eval"])
	elseif type(config[1]) == "string" then
		local groups = (config["groups"] or config[2]) or {}
		check_groups(groups)
		return M.new_regex(config[1], groups, config["filter"], config["priority"])
	elseif type(config[1]) == "function" then
		return M.new_eval(config[1], config["priority"])
	elseif type(config[1]) == "table" then
		local lines = {}

		for _, line in ipairs(config) do
			table.insert(lines, M.parse(line))
		end

		return M.new_multi_line(lines, config["priority"])
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
