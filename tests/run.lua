-- Spec files return named test functions. Each case runs even if another fails.
package.path = "mod/?.lua;mod/?/init.lua;" .. package.path

local total, failed = 0, 0
local function report(name, run)
	total = total + 1
	local ok, err = xpcall(run, debug.traceback)
	if ok then
		io.write("ok - " .. name .. "\n")
	else
		failed = failed + 1
		io.stderr:write("not ok - " .. name .. "\n" .. tostring(err) .. "\n")
	end
end

for _, path in ipairs(arg) do
	local ok, cases = pcall(dofile, path)
	if not ok then
		report(path, function()
			error(cases)
		end)
	elseif type(cases) ~= "table" or #cases == 0 then
		report(path, function()
			error("Spec must return a nonempty array of test cases")
		end)
	else
		for i, case in ipairs(cases) do
			if
				type(case) ~= "table"
				or type(case.name) ~= "string"
				or type(case.run) ~= "function"
			then
				report(path .. ":" .. i, function()
					error("Case requires name and run")
				end)
			else
				report(path .. ": " .. case.name, case.run)
			end
		end
	end
end

io.write(string.format("%d tests, %d failures\n", total, failed))
os.exit(total > 0 and failed == 0 and 0 or 1)
