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
