-- Add current directory to package.path
package.path = package.path .. ";lua/?.lua;lua/?/init.lua"

local Jovian = require("jovian")
local Config = require("jovian.config")

-- Helper to reset RTP and Config
local function reset()
    -- Remove jovian_queries from RTP if present
    local rtp = vim.opt.rtp:get()
    local new_rtp = {}
    for _, path in ipairs(rtp) do
        if not path:match("jovian_queries") then
            table.insert(new_rtp, path)
        end
    end
    vim.opt.rtp = new_rtp
    
    -- Reset config options to defaults
    Config.options = vim.deepcopy(Config.defaults)
end

local function test_default()
    reset()
    Jovian.setup({})
    
    local rtp = vim.opt.rtp:get()
    local found = false
    for _, path in ipairs(rtp) do
        if path:match("jovian_queries") then
            found = true
            break
        end
    end
    
    if found then
        print("PASS: Default config adds jovian_queries")
    else
        print("FAIL: Default config missing jovian_queries")
    end
end

local function test_disabled()
    reset()
    Jovian.setup({
        treesitter = {
            markdown_injection = false,
            magic_command_highlight = false,
        }
    })
    
    local rtp = vim.opt.rtp:get()
    local found = false
    for _, path in ipairs(rtp) do
        if path:match("jovian_queries") then
            found = true
            break
        end
    end
    
    if not found then
        print("PASS: Disabled config does not add jovian_queries")
    else
        print("FAIL: Disabled config added jovian_queries")
    end
end

local function test_partial()
    reset()
    Jovian.setup({
        treesitter = {
            markdown_injection = true,
            magic_command_highlight = false,
        }
    })
    
    local rtp = vim.opt.rtp:get()
    local found = false
    for _, path in ipairs(rtp) do
        if path:match("jovian_queries") then
            found = true
            break
        end
    end
    
    if found then
        print("PASS: Partial config adds jovian_queries")
    else
        print("FAIL: Partial config missing jovian_queries")
    end
end

test_default()
test_disabled()
test_partial()
