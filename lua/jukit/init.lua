local M = {}
local Config = require("jukit.config")
local Core = require("jukit.core")
local UI = require("jukit.ui")
local Utils = require("jukit.utils")

-- === ナビゲーション・編集 (initに残すのが自然なもの) ===

local function goto_next_cell()
    local cursor = vim.fn.line(".")
    local total = vim.api.nvim_buf_line_count(0)
    for i = cursor + 1, total do
        local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
        if line:match("^# %%%%") then
            vim.api.nvim_win_set_cursor(0, {i, 0})
            vim.cmd("normal! zz")
            local s, e = Utils.get_cell_range(i)
            UI.flash_range(s, e)
            return
        end
    end
    vim.notify("No next cell found", vim.log.levels.INFO)
end

local function goto_prev_cell()
    local cursor = vim.fn.line(".")
    for i = cursor - 1, 1, -1 do
        local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
        if line:match("^# %%%%") then
            vim.api.nvim_win_set_cursor(0, {i, 0})
            vim.cmd("normal! zz")
            local s, e = Utils.get_cell_range(i)
            UI.flash_range(s, e)
            return
        end
    end
    vim.notify("No previous cell found", vim.log.levels.INFO)
end

local function insert_cell_below()
    local _, e = Utils.get_cell_range()
    local new_id = Utils.generate_id()
    local lines = { "", "# %% id=\"" .. new_id .. "\"", "" }
    vim.api.nvim_buf_set_lines(0, e, e, false, lines)
    vim.api.nvim_win_set_cursor(0, {e + 3, 0})
    vim.cmd("startinsert") 
end

local function insert_cell_above()
    local s, _ = Utils.get_cell_range()
    local new_id = Utils.generate_id()
    local lines = { "# %% id=\"" .. new_id .. "\"", "", "" }
    vim.api.nvim_buf_set_lines(0, s - 1, s - 1, false, lines)
    vim.api.nvim_win_set_cursor(0, {s + 1, 0})
    vim.cmd("startinsert")
end

local function merge_cell_below()
    local _, e = Utils.get_cell_range()
    local total = vim.api.nvim_buf_line_count(0)
    if e >= total then return vim.notify("No cell below", vim.log.levels.WARN) end
    local line = vim.api.nvim_buf_get_lines(0, e, e + 1, false)[1]
    if line:match("^# %%%%") then
        vim.api.nvim_buf_set_lines(0, e, e + 1, false, {})
        vim.notify("Cells merged", vim.log.levels.INFO)
    else
        vim.notify("Could not find cell boundary below", vim.log.levels.WARN)
    end
end

-- === セットアップ ===
function M.setup(opts)
    Config.setup(opts)
    
    vim.api.nvim_create_user_command("JukitStart", Core.start_kernel, {})
    vim.api.nvim_create_user_command("JukitRun", Core.send_cell, {})
    vim.api.nvim_create_user_command("JukitSendSelection", Core.send_selection, { range = true })
    vim.api.nvim_create_user_command("JukitRunAll", Core.run_all_cells, {})
    vim.api.nvim_create_user_command("JukitRestart", Core.restart_kernel, {})
    
    vim.api.nvim_create_user_command("JukitOpen", function() UI.open_windows() end, {})
    vim.api.nvim_create_user_command("JukitToggle", UI.toggle_windows, {})
    vim.api.nvim_create_user_command("JukitClean", Core.clean_stale_cache, {})
    
    vim.api.nvim_create_user_command("JukitVars", Core.show_variables, {})
    vim.api.nvim_create_user_command("JukitView", Core.view_dataframe, { nargs = "?" })
    vim.api.nvim_create_user_command("JukitClear", UI.clear_repl, {})

    -- 編集系
    vim.api.nvim_create_user_command("JukitNextCell", goto_next_cell, {})
    vim.api.nvim_create_user_command("JukitPrevCell", goto_prev_cell, {})
    vim.api.nvim_create_user_command("JukitNewCellBelow", insert_cell_below, {})
    vim.api.nvim_create_user_command("JukitNewCellAbove", insert_cell_above, {})
    vim.api.nvim_create_user_command("JukitMergeBelow", merge_cell_below, {})
    
    -- 折りたたみ設定
    vim.opt.foldmethod = "expr"
    vim.opt.foldexpr = "getline(v:lnum)=~'^#\\ %%'?'0':'1'"
    vim.opt.foldlevel = 99

    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = "*",
        callback = function() 
            if vim.bo.filetype == "python" then Core.check_cursor_cell() end 
        end
    })
end

return M
