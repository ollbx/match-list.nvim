local M = {}

---Helper function to iterate a buffer line range in lua.
---@param buffer integer|nil The buffer to iterate. `nil` for the current buffer.
---@param first integer|nil The first row to scan. `nil` for row 1.
---@param last integer|nil The last row to scan. `nil` for the last row.
---@param fun fun(line: string, lnum: integer) The iterator function.
function M.iterate_lines(buffer, first, last, chunk, fun)
	buffer = buffer or vim.api.nvim_get_current_buf()
	first = first or 1
	last = last or vim.api.nvim_buf_line_count(buffer)

	-- Iterate the buffer in chunks.
	chunk = chunk or 1000
	local chunk_first = first

	while chunk_first <= last do
		-- Note: `chunk_first` and `chunk_last` are 1-based and end-inclusive.
		local chunk_last = math.min(chunk_first + chunk - 1, last)

		-- Retrieve the chunk.
		local lines = vim.api.nvim_buf_get_lines(
			buffer,
			chunk_first - 1, -- 1-based to 0-based (-1).
			chunk_last,      -- 1-based to 0-based (-1), but also end-inclusive to end-exclusive (+1).
			false)

		-- Scan line-by-line.
		for i, line in ipairs(lines) do
			-- 1-based line index.
			local lnum = chunk_first + i - 1
			fun(line, lnum)
		end

		chunk_first = chunk_last + 1
	end
end

---Creates a map from a group configuration and a list of values.
---@param groups table The group configuration.
---@param match string[] The list of matched values.
---@param base_data MatchList.MatchData? The base match data to extend.
---@return MatchList.MatchData data The match data.
function M.unfold_groups(groups, match, base_data)
	local data = vim.deepcopy(base_data or {})

	for i, group in ipairs(groups) do
		local index = string.find(group, ":")

		if index then
			-- Process "[flags]:[group]".
			local flags = string.sub(group, 1, index - 1)
			local name = string.sub(group, index + 1)
			local tag = string.sub(flags, 1, 1)

			if tag == "+" then
				local sep = string.sub(flags, 2, 2)

				if data[name] then
					data[name] = data[name] .. sep .. match[i]
				else
					data[name] = match[i]
				end
			else
				error("Invalid group flags: \"" .. flags .. "\"")
			end
		else
			-- Process "[group]".
			data[group] = match[i]
		end
	end

	-- Process direct a = b value assignments.
	for key, value in pairs(groups) do
		if type(key) ~= "number" then
			data[key] = value
		end
	end

	return data
end

---Creates a new scratch buffer with the given content.
---@param lines string[] The lines for the buffer.
---@return integer buffer The ID of the buffer.
function M.make_buffer(lines)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	return buffer
end

---Runs the given function and returns the execution time in ms.
---@param fun fun() The function to run.
---@return integer ms The number of milliseconds.
function M.time_ms(fun)
	local start = vim.uv.hrtime()
	fun()
	local diff = vim.uv.hrtime() - start
	return diff / 1000000
end

return M
