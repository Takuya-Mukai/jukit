vim.opt.rtp:prepend(".")
local Jovian = require("jovian")
local Core = require("jovian.core")
local UI = require("jovian.ui")
local State = require("jovian.state")

-- Helper to wait for a condition
local function wait_for(cond, timeout, msg)
    local ok = vim.wait(timeout or 5000, cond, 50)
    if not ok then
        print("TIMEOUT: " .. (msg or "Condition not met"))
        os.exit(1)
    end
end

-- Helper to check REPL content
local function check_repl(pattern)
    local repl_buf = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("JovianConsole") then
            repl_buf = buf
            break
        end
    end
    if not repl_buf then return false, "No REPL buffer" end
    local lines = vim.api.nvim_buf_get_lines(repl_buf, 0, -1, false)
    local content = table.concat(lines, "\n")
    if content:match(pattern) then return true end
    return false, content
end

-- Helper to wait for a condition
local function wait_for_repl(pattern, timeout, msg)
    local ok, content = vim.wait(timeout or 5000, function()
        local found, _ = check_repl(pattern)
        return found
    end, 50)
    if not ok then
        local _, current_content = check_repl(pattern)
        print("TIMEOUT: " .. (msg or "Condition not met"))
        print("REPL Content:\n" .. (current_content or "nil"))
        os.exit(1)
    end
end

-- Setup
print("Setting up Jovian...")
Jovian.setup({ python_interpreter = "python3" })

-- Create a dummy buffer to act as the code buffer
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, "test.py")
vim.api.nvim_set_current_buf(buf)
vim.bo.filetype = "python"
local main_win = vim.api.nvim_get_current_win()

-- Test 1: Simple Execution
print("Running Test 1: Simple Execution")
vim.cmd("JovianOpen")
vim.cmd("JovianStart")
wait_for(function() return State.job_id ~= nil end, 5000, "Kernel start")
-- Wait a bit for kernel to be fully ready
vim.wait(1000)

vim.api.nvim_set_current_win(main_win)
Core.send_payload("print(1 + 1)", "test1", "test.py")
wait_for_repl("2", 5000, "Output '2'")
print("PASS: Simple Execution")

-- Test 2: State Persistence
print("Running Test 2: State Persistence")
vim.api.nvim_set_current_win(main_win)
Core.send_payload("a = 50", "test2a", "test.py")
vim.wait(500)
Core.send_payload("print(a)", "test2b", "test.py")
wait_for_repl("50", 5000, "Output '50'")
print("PASS: State Persistence")

-- Test 3: Error Handling
print("Running Test 3: Error Handling")
vim.api.nvim_set_current_win(main_win)
print("DEBUG: main_win: " .. main_win .. " buf: " .. vim.api.nvim_win_get_buf(main_win))
Core.send_payload("raise ValueError('TestError')", "test3", "test.py")
wait_for_repl("ValueError: TestError", 5000, "Error Output")

-- Check diagnostics
vim.wait(500) -- Allow diagnostic update
print("DEBUG: Checking diagnostics on buf: " .. buf)
local diags = vim.diagnostic.get(buf, { namespace = State.diag_ns })
if #diags > 0 then
    local found = false
    for _, d in ipairs(diags) do
        if d.message:match("ValueError") then
            found = true
            break
        end
    end
    if found then
        print("PASS: Error Diagnostics")
    else
        print("FAIL: Diagnostic message mismatch")
        os.exit(1)
    end
else
    print("FAIL: Error Diagnostics not found")
    os.exit(1)
end

-- Test 4: Window Focus
print("Running Test 4: Window Focus")
local current_win = vim.api.nvim_get_current_win()
vim.cmd("JovianOpen") -- Should already be open, but calling again to verify focus logic
local new_win = vim.api.nvim_get_current_win()
if current_win == new_win then
    print("PASS: Window Focus Preserved")
else
    print("FAIL: Window Focus Changed")
    os.exit(1)
end

print("ALL TESTS PASSED")
vim.cmd("qall!")
