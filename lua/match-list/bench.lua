local M = {}
local log_buffer = -1

local function bench_with(name, buffer, scanner)
	local Util = require("match-list.util")

	-- Build the list of matches.
	local matches = {}

	local time_ms = Util.time_ms(function()
		matches = scanner:scan(buffer)
	end)

	local lines = vim.api.nvim_buf_line_count(buffer)
	local scan_lps = 1000 * lines / time_ms

	vim.api.nvim_buf_set_lines(log_buffer, -2, -2, false, {
		"# " .. name,
		"",
		"Scanned buffer in " .. time_ms .. "ms (" .. string.format("%.2f", scan_lps) .. " l/s)",
		#matches .. " matches found",
		"First match: " .. string.gsub(vim.inspect(matches[1]), "%s+", " "),
		"",
	})
end

---Runs a benchmark of matching mechanisms.
function M.bench()
	local Util = require("match-list.util")
	local Scanner = require("match-list.scanner")
	local lpeg = require("lpeg")
	local regex_scan = Scanner.new_regex([[error: \(.*\)]], { "message" })
	local match_scan = Scanner.new_match([[error: (.*)]], { "message" })

	local lpeg_scan = Scanner.new_lpeg(
		lpeg.P("error:") * lpeg.S(" ")^0 * lpeg.C(lpeg.P(1)^1),
		{ "message" }
	)

	local eval_scan = Scanner.new_eval(function(line)
		if string.sub(line, 1, 6) == "error:" then
			return { message = string.sub(line, 8) }
		end
	end)

	if not vim.api.nvim_buf_is_valid(log_buffer) then
		log_buffer = vim.api.nvim_create_buf(false, true)
		vim.bo[log_buffer].ft = "markdown"
	end

	vim.api.nvim_buf_set_lines(log_buffer, 0, -1, false, {})
	vim.api.nvim_win_set_buf(0, log_buffer)

	local lines = 500000
	local buffer = vim.api.nvim_create_buf(false, true)

	-- Prepare a large buffer.
	local prepare_ms = Util.time_ms(function()
		for i=1,lines do
			local line = "line " .. i
			if i % 1000 == 0 then line = "error: line " .. i end
			vim.api.nvim_buf_set_lines(buffer, i-1, i, false, { line })
		end
	end)

	vim.api.nvim_buf_set_lines(log_buffer, -2, -2, false, {
		"# Preparation",
		"",
		"Prepared buffer with " .. lines .. " lines in " .. prepare_ms .. "ms",
		"",
	})

	bench_with("Eval scanner", buffer, eval_scan)
	bench_with("Regex scanner", buffer, regex_scan)
	bench_with("Match scanner", buffer, match_scan)
	bench_with("LPEG scanner", buffer, lpeg_scan)

	vim.api.nvim_buf_delete(buffer, { force = true })
end

return M
