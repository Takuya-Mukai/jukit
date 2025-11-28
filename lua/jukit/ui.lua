local M = {}
local Config = require("jukit.config")
local State = require("jukit.state")

-- === 通知 ===
function M.send_notification(msg)
    if vim.fn.executable("notify-send") == 1 then
        vim.fn.jobstart({"notify-send", "Jukit Task Finished", msg}, {detach=true})
    elseif vim.fn.executable("osascript") == 1 then
        vim.fn.jobstart({"osascript", "-e", 'display notification "'..msg..'" with title "Jukit"'}, {detach=true})
    else
        vim.notify(msg, vim.log.levels.INFO)
    end
end

-- === バッファ・ウィンドウ管理 ===
function M.get_or_create_buf(name)
    local existing = vim.fn.bufnr(name)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then return existing end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    return buf
end

function M.append_to_repl(text, hl_group)
    if not (State.buf.output and vim.api.nvim_buf_is_valid(State.buf.output)) then return end
    local lines = type(text) == "table" and text or vim.split(text, "\n")
    vim.api.nvim_buf_set_lines(State.buf.output, -1, -1, false, lines)
    local last_line = vim.api.nvim_buf_line_count(State.buf.output)
    if hl_group then
        for i = 0, #lines - 1 do
            vim.api.nvim_buf_add_highlight(State.buf.output, -1, hl_group, last_line - #lines + i, 0, -1)
        end
    end
    if State.win.output and vim.api.nvim_win_is_valid(State.win.output) then
        vim.api.nvim_win_set_cursor(State.win.output, {last_line, 0})
    end
end

function M.append_stream_text(text)
    if not (State.buf.output and vim.api.nvim_buf_is_valid(State.buf.output)) then return end
    local buf = State.buf.output
    if text:find("\r") then
        local parts = vim.split(text, "\r")
        local last_part = parts[#parts]
        local count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, count - 1, count, false, {last_part})
    else
        local lines = vim.split(text, "\n")
        if lines[#lines] == "" and #lines > 1 then table.remove(lines, #lines) end
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    end
    if State.win.output and vim.api.nvim_win_is_valid(State.win.output) then
        local count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(State.win.output, {count, 0})
    end
end

function M.flash_range(start_line, end_line)
    vim.api.nvim_buf_clear_namespace(0, State.hl_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(0, State.hl_ns, start_line - 1, 0, {
        end_row = end_line, hl_group = Config.options.flash_highlight_group, hl_eol = true, priority = 200,
    })
    vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(0) then vim.api.nvim_buf_clear_namespace(0, State.hl_ns, 0, -1) end
    end, Config.options.flash_duration)
end

function M.open_windows(target_win)
    local return_to = target_win or vim.api.nvim_get_current_win()
    if not (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) then
        vim.cmd("vsplit")
        vim.cmd("wincmd L")
        State.win.preview = vim.api.nvim_get_current_win()
        local width = math.floor(vim.o.columns * (Config.options.preview_width_percent / 100))
        vim.api.nvim_win_set_width(State.win.preview, width)
        local pbuf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(State.win.preview, pbuf)
    end
    if not (State.win.output and vim.api.nvim_win_is_valid(State.win.output)) then
        if vim.api.nvim_win_is_valid(return_to) then vim.api.nvim_set_current_win(return_to) end
        vim.cmd("split")
        vim.cmd("wincmd j")
        State.win.output = vim.api.nvim_get_current_win()
        State.buf.output = M.get_or_create_buf("JukitConsole")
        if vim.api.nvim_buf_line_count(State.buf.output) <= 1 then
            vim.api.nvim_buf_set_lines(State.buf.output, 0, -1, false, {"[Jukit Console Ready]"})
        end
        vim.api.nvim_win_set_buf(State.win.output, State.buf.output)
        local height = math.floor(vim.o.lines * (Config.options.repl_height_percent / 100))
        vim.api.nvim_win_set_height(State.win.output, height)
    end
    vim.schedule(function()
        if return_to and vim.api.nvim_win_is_valid(return_to) then
            vim.api.nvim_set_current_win(return_to)
        end
    end)
end

function M.close_windows()
    if State.win.preview and vim.api.nvim_win_is_valid(State.win.preview) then vim.api.nvim_win_close(State.win.preview, true) end
    if State.win.output and vim.api.nvim_win_is_valid(State.win.output) then vim.api.nvim_win_close(State.win.output, true) end
    State.win.preview, State.win.output = nil, nil
    State.current_preview_file = nil
end

function M.toggle_windows()
    if (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) or 
       (State.win.output and vim.api.nvim_win_is_valid(State.win.output)) then
        M.close_windows()
    else
        M.open_windows()
    end
end

function M.open_markdown_preview(filepath)
    if not (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) then return end
    local abs_filepath = vim.fn.fnamemodify(filepath, ":p")
    local file_dir = vim.fn.fnamemodify(abs_filepath, ":h")
    State.current_preview_file = abs_filepath
    local cur_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(State.win.preview)
    vim.cmd("lcd " .. file_dir)
    vim.cmd("edit! " .. abs_filepath)
    vim.bo.filetype = "markdown"
    vim.bo.buftype = "" 
    vim.wo.wrap = true
    vim.schedule(function()
        if vim.api.nvim_win_is_valid(cur_win) then vim.api.nvim_set_current_win(cur_win) end
    end)
end

function M.set_cell_status(bufnr, cell_id, status, msg)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
        if line:find('id="' .. cell_id .. '"', 1, true) then
            local hl_group = "Comment"
            if status == "running" then hl_group = "WarningMsg"
            elseif status == "done" then hl_group = "String"
            elseif status == "error" then hl_group = "ErrorMsg" end
            
            vim.api.nvim_buf_clear_namespace(bufnr, State.status_ns, i - 1, i)
            vim.api.nvim_buf_set_extmark(bufnr, State.status_ns, i - 1, 0, {
                virt_text = {{ "  " .. msg, hl_group }},
                virt_text_pos = "eol",
            })
            return
        end
    end
end

function M.show_variables(vars)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    local lines = { "VARIABLE             TYPE             VALUE/INFO", "------------------------------------------------------------" }
    for _, v in ipairs(vars) do
        local name = v.name .. string.rep(" ", 20 - #v.name)
        local type_name = v.type .. string.rep(" ", 16 - #v.type)
        table.insert(lines, name .. type_name .. v.info)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1)
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = width, height = height, row = row, col = col,
        style = "minimal", border = "rounded", title = " Variables ", title_pos = "center"
    })
    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

function M.show_dataframe(data)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    local SEPARATOR = " │ " 
    local PADDING = 1
    
    local headers = { "" } 
    for _, c in ipairs(data.columns) do table.insert(headers, tostring(c)) end
    
    local col_widths = {}
    for i, h in ipairs(headers) do col_widths[i] = vim.fn.strdisplaywidth(h) end

    for i, row in ipairs(data.data) do
        local idx = tostring(data.index[i])
        col_widths[1] = math.max(col_widths[1], vim.fn.strdisplaywidth(idx))
        for j, val in ipairs(row) do
            local s = tostring(val)
            col_widths[j+1] = math.max(col_widths[j+1] or 0, vim.fn.strdisplaywidth(s))
        end
    end

    local function pad_str(s, w) 
        local vis_w = vim.fn.strdisplaywidth(s)
        return string.rep(" ", PADDING) .. s .. string.rep(" ", w - vis_w + PADDING)
    end

    local fmt_lines = {}
    local header_line = ""
    for i, h in ipairs(headers) do 
        header_line = header_line .. pad_str(h, col_widths[i]) .. (i < #headers and SEPARATOR or "")
    end
    table.insert(fmt_lines, header_line)

    local sep_line = ""
    for i, w in ipairs(col_widths) do
        local total_w = w + (PADDING * 2)
        sep_line = sep_line .. string.rep("─", total_w) .. (i < #headers and "─┼─" or "")
    end
    table.insert(fmt_lines, sep_line)

    for i, row in ipairs(data.data) do
        local line_str = pad_str(tostring(data.index[i]), col_widths[1]) .. SEPARATOR
        for j, val in ipairs(row) do
            line_str = line_str .. pad_str(tostring(val), col_widths[j+1]) .. (j < #row and SEPARATOR or "")
        end
        table.insert(fmt_lines, line_str)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, fmt_lines)
    vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1)
    
    local index_col_width = col_widths[1] + (PADDING * 2) 
    for i = 2, #fmt_lines - 1 do
        vim.api.nvim_buf_add_highlight(buf, -1, "Statement", i, 0, index_col_width)
        local current_pos = 0
        for j, w in ipairs(col_widths) do
            current_pos = current_pos + w + (PADDING * 2)
            if j < #col_widths then
                vim.api.nvim_buf_add_highlight(buf, -1, "Comment", i, current_pos, current_pos + #SEPARATOR)
                current_pos = current_pos + #SEPARATOR
            end
        end
    end

    local width = math.floor(vim.o.columns * 0.85)
    local height = math.floor(vim.o.lines * 0.7)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = width, height = height, row = row, col = col,
        style = "minimal", border = "rounded", title = " " .. data.name .. " ", title_pos = "center"
    })
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

function M.clear_repl()
    if State.buf.output and vim.api.nvim_buf_is_valid(State.buf.output) then
        vim.api.nvim_buf_set_lines(State.buf.output, 0, -1, false, {"[Jukit Console Cleared]"})
    end
end

return M
