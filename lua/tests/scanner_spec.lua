describe("match-list.scanner", function()
	local Scanner = require("match-list.scanner")
	local Util = require("match-list.util")

	local lines = {
		"this is a test line",  -- 1
		"this is another line", -- 2
		"12 bottles of beer",   -- 3
		"no more microwaves",   -- 4
		"25 bottles of beer",   -- 5
		"reticulating splines", -- 6
	}

	it("should support regex", function()
		local buffer = Util.make_buffer(lines)
		local expr = [[^\(\d\+\) bottles of beer]]
		local scanner = Scanner.parse({ expr, { "count", type = "info" } })
		local matches = scanner:scan(buffer)

		assert.are.same(1, scanner:get_lines())
		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 3, data = { count = "12", type = "info" } },
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = "25", type = "info" } },
		}, matches)

		-- Try a filter function.
		scanner = Scanner.parse({
			expr, { "count" },
			filter = function(data)
				local count = tonumber(data["count"])

				if count > 15 then
					return { count = count * 2, type = "info" }
				end
			end
		})

		matches = scanner:scan(buffer)

		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = 50, type = "info" } },
		}, matches)
	end)

	it("should support lua match", function()
		local buffer = Util.make_buffer(lines)
		local expr = [[^(%d+) bottles of beer]]
		local scanner = Scanner.parse({ match = expr, { "count", type = "info" } })
		local matches = scanner:scan(buffer)

		assert.are.same(1, scanner:get_lines())
		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 3, data = { count = "12", type = "info" } },
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = "25", type = "info" } },
		}, matches)

		-- Try a filter function.
		scanner = Scanner.parse({
			match = expr, { "count" },
			filter = function(data)
				local count = tonumber(data["count"])

				if count > 15 then
					return { count = count * 2, type = "info" }
				end
			end
		})

		matches = scanner:scan(buffer)

		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = 50, type = "info" } },
		}, matches)
	end)

	it("should support lpeg", function()
		local lpeg = require("lpeg")
		local buffer = Util.make_buffer(lines)
		local expr = lpeg.C(lpeg.R("09")^1) * lpeg.P(" bottles of beer")
		local scanner = Scanner.parse({ lpeg = expr, { "count", type = "info" } })
		local matches = scanner:scan(buffer)

		assert.are.same(1, scanner:get_lines())
		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 3, data = { count = "12", type = "info" } },
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = "25", type = "info" } },
		}, matches)

		-- Try a filter function.
		scanner = Scanner.parse({
			lpeg = expr, { "count" },
			filter = function(data)
				local count = tonumber(data["count"])

				if count > 15 then
					return { count = count * 2, type = "info" }
				end
			end
		})

		matches = scanner:scan(buffer)

		assert.are.same({
			{ buffer = buffer, lines = 1, priority = 0, lnum = 5, data = { count = 50, type = "info" } },
		}, matches)
	end)

	it("should support multi-line", function()
		local buffer = Util.make_buffer(lines)

		local scanner = Scanner.parse({
			{ [[^\(\d\+\) bottles of beer]], { "count" } },
			{ match = [[no (%w+) microwaves]], { "more", type = "info" } },
		})

		local expect = {
			buffer = buffer,
			lines = 2,
			priority = 0,
			lnum = 3,
			data = { count = "12", more = "more", type = "info" },
		}

		assert.are.same(2, scanner:get_lines())

		local matches = scanner:scan(buffer)
		assert.are.same({ expect }, matches)

		-- If the first line is in the range, the whole thing should match.
		matches = scanner:scan(buffer, 1, 3)
		assert.are.same({ expect }, matches)

		-- If the first line is not in range, nothing should match.
		matches = scanner:scan(buffer, 1, 2)
		assert.are.same({}, matches)
	end)

	it("should support filters", function()
		local buffer = Util.make_buffer(lines)

		local scanner = Scanner.parse({
			{ [[this \(.*\)]], { "message" } },
			{ match = [[this (.*)]], { "+:message" } },
			priority = 1,
		})

		local expect = {
			buffer = buffer,
			lines = 2,
			priority = 1,
			lnum = 1,
			data = { message = "is a test lineis another line" },
		}

		assert.are.same(2, scanner:get_lines())

		local matches = scanner:scan(buffer)
		assert.are.same({ expect }, matches)

		scanner = Scanner.parse({
			{ [[this \(.*\)]], { "message" } },
			{ match = [[this (.*)]], { "+,:message" } },
		})

		expect = {
			buffer = buffer,
			lines = 2,
			priority = 0,
			lnum = 1,
			data = { message = "is a test line,is another line" },
		}

		assert.are.same(2, scanner:get_lines())

		matches = scanner:scan(buffer)
		assert.are.same({ expect }, matches)
	end)
end)
