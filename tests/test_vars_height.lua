vim.opt.rtp:prepend(".")
local Jovian = require("jovian")
local UI = require("jovian.ui")
local State = require("jovian.state")
local Config = require("jovian.config")

local function wait_for(cond, timeout, msg)
    local ok = vim.wait(timeout or 5000, cond, 50)
    if not ok then
        print("TIMEOUT: " .. (msg or "Condition not met"))
        os.exit(1)
    end
end

-- Setup with specific height
print("Setting up Jovian with vars_pane_height=5...")
Jovian.setup({ vars_pane_height = 5 })

-- Create dummy buffer
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)

-- Open Preview first to force "aboveleft split" behavior
vim.cmd("JovianOpen")
wait_for(function() return State.win.preview and vim.api.nvim_win_is_valid(State.win.preview) end, 1000, "Preview Open")

-- Toggle Vars Pane
print("Toggling Vars Pane...")
vim.cmd("JovianToggleVars")
wait_for(function() return State.win.variables and vim.api.nvim_win_is_valid(State.win.variables) end, 1000, "Vars Pane Open")

-- Check Height
local win = State.win.variables
local height = vim.api.nvim_win_get_height(win)
local expected_height = 5

print("Window Height: " .. height)
print("Expected Height: " .. expected_height)

if height == expected_height then
    print("PASS: Height Correct")
else
    print("FAIL: Height Incorrect")
    os.exit(1)
end

vim.cmd("qall!")
