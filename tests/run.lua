-- Runs the tests with a plain Lua interpreter: lua5.4 tests/run.lua
-- Run it from the repository root. tools/test.sh does that.

Test = { passed = 0, failed = 0, failures = {} }

local current

function Test.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
	end
end

function Test.case(name, fn)
	current = name
	local ok, err = pcall(fn)
	if ok then
		Test.passed = Test.passed + 1
	else
		Test.failed = Test.failed + 1
		Test.failures[#Test.failures + 1] = string.format("FAIL %s\n     %s", name, tostring(err))
	end
end

dofile("mod/Code/Rules.lua")
dofile("mod/Code/Memory.lua")
dofile("mod/Code/Interrupt.lua")

local files = { "tests/test_rules.lua", "tests/test_memory.lua", "tests/test_interrupt.lua", "tests/test_engine.lua",
	"tests/test_ui.lua" }
for _, f in ipairs(files) do
	local chunk, err = loadfile(f)
	if not chunk then
		Test.failed = Test.failed + 1
		Test.failures[#Test.failures + 1] = "LOAD " .. f .. ": " .. tostring(err)
	else
		chunk()
	end
end

-- test_engine.lua replaces print to capture the mod's log lines.
for _, line in ipairs(Test.failures) do
	io.write(line, "\n")
end
io.write(string.format("%d passed, %d failed\n", Test.passed, Test.failed))
os.exit(Test.failed == 0 and 0 or 1)
