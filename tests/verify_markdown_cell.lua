package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local Jovian = require("jovian")
local Utils = require("jovian.utils")

print("Verifying Markdown Cell Insertion...")

-- Mock vim API
_G.vim = {
    api = {
        nvim_buf_line_count = function() return 10 end,
        nvim_buf_get_lines = function() return {"# %%"} end,
        nvim_buf_set_lines = function(buf, start, end_, strict, lines)
            print("Inserted lines at " .. start)
            for _, line in ipairs(lines) do
                print("  " .. line)
                if line:match("# %%%% %[markdown%]") then
                    print("PASS: Markdown header found")
                end
            end
        end,
        nvim_win_set_cursor = function() end,
        nvim_create_user_command = function(name, func, opts)
            if name == "JovianNewMarkdownCellBelow" then
                print("PASS: Command registered")
                -- Execute it to test logic
                -- Mock Utils.get_cell_range
                Utils.get_cell_range = function() return 1, 5 end
                func()
            end
        end,
        nvim_create_autocmd = function() end,
    },
    fn = {
        line = function() return 1 end,
        stdpath = function() return "/tmp" end,
        fnamemodify = function() return "/tmp" end,
        isdirectory = function() return 1 end,
        filereadable = function() return 0 end,
    },
    cmd = function(cmd) print("CMD: " .. cmd) end,
    notify = function() end,
    split = function() return {} end,
    opt = { foldmethod = "", foldexpr = "", foldlevel = 0 },
    bo = { filetype = "" },
    tbl_keys = function() return {} end,
}

-- Mock Config
local Config = require("jovian.config")
Config.setup = function() end

-- Load Init (triggers setup and command registration)
Jovian.setup({})

print("Verification Complete")
vim.cmd("q")
