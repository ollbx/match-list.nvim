local M = {
	scratch_win = -1,
	scratch_buf = -1,
	matches_win = -1,
	matches_buf = -1,
	config_win = -1,
	config_buf = -1,
	tracker = nil,
}

function M.open()
	local Tracker = require("match-list.tracker")

	-- Create buffers.
	if not vim.api.nvim_buf_is_valid(M.scratch_buf) then
		M.scratch_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[M.scratch_buf].ft = "markdown"

		vim.api.nvim_buf_set_lines(M.scratch_buf, 0, -1, false, {
			"# Scratch buffer",
			"",
			"This buffer contains test data that is matched against.",
			"You can edit the data in real-time.",
			"",
			"# Keymap in this buffer:",
			"",
			"- tg: select the match group to use",
			"- tf: go to the first match",
			"- tn: go to the next match",
			"- tp: go to the previous match",
			"- tl: go to the last match",
			"- tx: reset the item selection",
			"",
			"error: This is a test error line.",
			"file: some_testfile.txt:123",
			"",
			"fatal error: This is another test error line.",
			"",
			"This is a normal line.",
			"warning: This is a warning line.",
		})
	end

	if not vim.api.nvim_buf_is_valid(M.matches_buf) then
		M.matches_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[M.matches_buf].ft = "lua"
	end

	if not vim.api.nvim_buf_is_valid(M.config_buf) then
		M.config_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[M.config_buf].ft = "lua"

		vim.api.nvim_buf_set_lines(M.config_buf, 0, -1, false, {
			"-- This is the configuration of the match groups.",
			"--",
			"-- Keymap in this buffer:",
			"-- tr: reload the filter configuration",
			"",
			"local lpeg = require(\"lpeg\")",
			"",
			"return {",
			"	default = {",
			"		{ [[\\(error\\|warning\\): \\(.*\\)]], { \"type\", \"message\" } },",
			"	},",
			"	priority = {",
			"		{ [[\\(error\\|warning\\): \\(.*\\)]], { \"type\", \"message\", fatal = false } },",
			"		{ [[fatal error: \\(.*\\)]], { type = \"error\", \"message\", fatal = true }, priority = 1 },",
			"	},",
			"	multi_line = {",
			"		{",
			"			{ [[\\(error\\|warning\\): \\(.*\\)]], { \"type\", \"message\" } },",
			"			function(line, data)",
			"				if string.sub(line, 1, 6) == \"file: \" then",
			"					data.filename = string.sub(line, 7)",
			"					return data",
			"				end",
			"			end",
			"		}",
			"	},",
			"	warning_only = {",
			"		{ match = [[(warning): (.*)]], { \"type\", \"message\" } },",
			"	},",
			"	with_filter = {",
			"		{",
			"			regex = [[\\(error\\|warning\\): \\(.*\\)]], ",
			"			groups = { \"type\", \"message\" },",
			"			filter = function(data)",
			"				if not string.find(data.message, \"another\") then",
			"					return data",
			"				end",
			"			end",
			"		},",
			"	},",
			"	lpeg = {",
			"		{",
			"			lpeg = lpeg.C(lpeg.P(\"error\")+lpeg.P(\"warning\")) * lpeg.P(\": \") * lpeg.C(lpeg.P(1)^0),",
			"			{ \"type\", \"message\" }",
			"		},",
			"	},",
			"}",
		})
	end

	-- Open windows.
	if not vim.api.nvim_win_is_valid(M.scratch_win) then
		M.scratch_win = vim.api.nvim_get_current_win()
	end

	if not vim.api.nvim_win_is_valid(M.matches_win) then
		M.matches_win = vim.api.nvim_open_win(M.matches_buf, false, {
			split = "right",
			win = M.scratch_win,
		})
	end

	if not vim.api.nvim_win_is_valid(M.config_win) then
		M.config_win = vim.api.nvim_open_win(M.config_buf, false, {
			split = "below",
			win = M.matches_win,
		})
	end

	vim.api.nvim_win_set_buf(M.scratch_win, M.scratch_buf)
	vim.api.nvim_win_set_buf(M.matches_win, M.matches_buf)
	vim.api.nvim_win_set_buf(M.config_win,  M.config_buf)

	-- Create a tracker and attack it to the buffer.
	if not M.tracker then
		M.tracker = Tracker.new()
		M.tracker:attach(M.scratch_buf)

		M.tracker:set_update_hook(function(matches)
			table.sort(matches, function(a, b) return a.lnum < b.lnum end)
			local data = vim.inspect(matches)

			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(M.matches_win)
			vim.api.nvim_buf_set_lines(M.matches_buf, 0, -1, false, {
				"-- Currently visible matches:", "", ""
			})

			vim.api.nvim_win_set_cursor(M.matches_win, { 3, 0 })
			vim.api.nvim_paste(data, true, -1)
			vim.api.nvim_set_current_win(win)
		end)

		local function load_config()
			local lines = vim.api.nvim_buf_get_lines(M.config_buf, 0, -1, false)

			local code = [[
				require("match-list.debug").tracker:setup_groups(
					require("match-list.scanner").parse_groups(
						(function()
							]] .. table.concat(lines, "\n") .. [[
						end)()
					)
				)
			]]

			vim.fn.luaeval(code)
		end

		load_config()

		vim.keymap.set("n", "tr", function()
			local status, result = pcall(load_config)

			if status then
				vim.notify("Config reloaded.", vim.log.levels.INFO)
			else
				vim.notify("Error: " .. result, vim.log.levels.ERROR)
			end
		end, { buffer = M.config_buf })

		vim.keymap.set("n", "tg", function()
			local groups = M.tracker:get_available_groups()

			vim.ui.select(groups, {}, function(group)
				M.tracker:set_group(group)
			end)
		end, { buffer = M.scratch_buf })

		vim.keymap.set("n", "tf", function() M.tracker:first() end, { buffer = M.scratch_buf })
		vim.keymap.set("n", "tn", function() M.tracker:next() end, { buffer = M.scratch_buf })
		vim.keymap.set("n", "tp", function() M.tracker:prev() end, { buffer = M.scratch_buf })
		vim.keymap.set("n", "tl", function() M.tracker:last() end, { buffer = M.scratch_buf })
		vim.keymap.set("n", "tx", function() M.tracker:unselect() end, { buffer = M.scratch_buf })
	end
end

return M
