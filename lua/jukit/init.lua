local M = {}

-- === 設定 (Configuration) ===
local default_config = {
    preview_width_percent = 40,
    repl_height_percent = 30,
    preview_image_ratio = 0.6,
    repl_image_ratio = 0.3,
    flash_highlight_group = "Visual",
    flash_duration = 300,
    python_interpreter = "python3", 
    notify_threshold = 10,
}
M.config = vim.deepcopy(default_config)

-- === 内部状態 (Internal State) ===
local State = {
    job_id = nil,
    buf = { output = nil, preview = nil },
    win = { output = nil, preview = nil },
    hl_ns = vim.api.nvim_create_namespace("JukitCellHighlight"),
    status_ns = vim.api.nvim_create_namespace("JukitStatus"),
    diag_ns = vim.api.nvim_create_namespace("JukitDiagnostics"),

    current_preview_file = nil,
    cell_buf_map = {},
    cell_start_time = {},   -- ★追加: { cell_id: start_timestamp }
    cell_start_line = {},   -- ★追加: { cell_id: start_line_num } (エラー診断用)
}

local function set_cell_status(bufnr, cell_id, status, msg)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then return end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    for i, line in ipairs(lines) do
        if line:find('id="' .. cell_id .. '"', 1, true) then
            local hl_group = "Comment"
            if status == "running" then hl_group = "WarningMsg"
            elseif status == "done" then hl_group = "String" end
            
            -- 古い表示を消す
            vim.api.nvim_buf_clear_namespace(bufnr, State.status_ns, i - 1, i)
            
            -- 新しい表示を出す
            vim.api.nvim_buf_set_extmark(bufnr, State.status_ns, i - 1, 0, {
                virt_text = {{ "  " .. msg, hl_group }},
                virt_text_pos = "eol",
            })
            return
        end
    end
end

local function send_notification(msg)
    -- Linux (notify-send) または Mac (osascript) を検出して実行
    if vim.fn.executable("notify-send") == 1 then
        vim.fn.jobstart({"notify-send", "Jukit Task Finished", msg}, {detach=true})
    elseif vim.fn.executable("osascript") == 1 then
        vim.fn.jobstart({"osascript", "-e", 'display notification "'..msg..'" with title "Jukit"'}, {detach=true})
    else
        vim.notify(msg, vim.log.levels.INFO)
    end
end

-- === ユーティリティ (Utils) ===
local Utils = {}

function Utils.generate_id()
    math.randomseed(os.time())
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    local id = ""
    for i = 1, 8 do
        local rand = math.random(#chars)
        id = id .. string.sub(chars, rand, rand)
    end
    return id
end

function Utils.get_cell_range(lnum)
    local cursor = lnum or vim.fn.line(".")
    local total = vim.api.nvim_buf_line_count(0)
    local s, e = cursor, cursor
    
    -- 上方向に検索
    while s > 1 do
        local line = vim.api.nvim_buf_get_lines(0, s - 1, s, false)[1]
        if line:match("^# %%%%") then break end
        s = s - 1
    end
    
    -- 下方向に検索
    while e < total do
        local line = vim.api.nvim_buf_get_lines(0, e, e + 1, false)[1]
        if line:match("^# %%%%") then break end
        e = e + 1
    end
    
    return s, e
end

function Utils.ensure_cell_id(line_num, line_content)
    local id = line_content:match("id=\"([%w%-_]+)\"")
    if id then return id end
    
    id = Utils.generate_id()
    if line_content:match("^# %%%%") then
        local new_line = line_content .. " id=\"" .. id .. "\""
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {new_line})
    end
    return id
end

function Utils.get_current_cell_id(lnum)
    local s, _ = Utils.get_cell_range(lnum)
    local lines = vim.api.nvim_buf_get_lines(0, s - 1, s, false)
    local line = lines[1] or ""
    
    local id = line:match("id=\"([%w%-_]+)\"")
    if id then return id end
    
    if line:match("^# %%%%") then
        return Utils.ensure_cell_id(s, line)
    end
    
    return "scratchpad"
end

-- === UI操作 (UI Operations) ===
local UI = {}

function UI.get_or_create_buf(name)
    local existing = vim.fn.bufnr(name)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then return existing end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    return buf
end

function UI.append_to_repl(text, hl_group)
    if not (State.buf.output and vim.api.nvim_buf_is_valid(State.buf.output)) then return end
    
    local lines = type(text) == "table" and text or vim.split(text, "\n")
    local buf = State.buf.output
    
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    local last_line = vim.api.nvim_buf_line_count(buf)
    
    if hl_group then
        for i = 0, #lines - 1 do
            vim.api.nvim_buf_add_highlight(buf, -1, hl_group, last_line - #lines + i, 0, -1)
        end
    end
    
    if State.win.output and vim.api.nvim_win_is_valid(State.win.output) then
        vim.api.nvim_win_set_cursor(State.win.output, {last_line, 0})
    end
end

function UI.append_stream_text(text)
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

function UI.flash_range(start_line, end_line)
    vim.api.nvim_buf_clear_namespace(0, State.hl_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(0, State.hl_ns, start_line - 1, 0, {
        end_row = end_line,
        hl_group = M.config.flash_highlight_group,
        hl_eol = true, priority = 200,
    })
    vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(0) then
            vim.api.nvim_buf_clear_namespace(0, State.hl_ns, 0, -1)
        end
    end, M.config.flash_duration)
end

function UI.open_windows(target_win)
    -- 戻るべきウィンドウIDを確保（指定がなければ現在のウィンドウ）
    local return_to = target_win or vim.api.nvim_get_current_win()

    -- Preview Window
    if not (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) then
        vim.cmd("vsplit")
        vim.cmd("wincmd L")
        State.win.preview = vim.api.nvim_get_current_win()
        local width = math.floor(vim.o.columns * (M.config.preview_width_percent / 100))
        vim.api.nvim_win_set_width(State.win.preview, width)
        
        local pbuf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(State.win.preview, pbuf)
    end

    -- REPL Window
    if not (State.win.output and vim.api.nvim_win_is_valid(State.win.output)) then
        -- レイアウト崩れ防止のため、一旦戻り先ウィンドウにフォーカスしてから分割
        if vim.api.nvim_win_is_valid(return_to) then vim.api.nvim_set_current_win(return_to) end
        
        vim.cmd("split")
        vim.cmd("wincmd j")
        State.win.output = vim.api.nvim_get_current_win()
        State.buf.output = UI.get_or_create_buf("JukitConsole")
        
        if vim.api.nvim_buf_line_count(State.buf.output) <= 1 then
            vim.api.nvim_buf_set_lines(State.buf.output, 0, -1, false, {"[Jukit Console Ready]"})
        end
        vim.api.nvim_win_set_buf(State.win.output, State.buf.output)
        
        local height = math.floor(vim.o.lines * (M.config.repl_height_percent / 100))
        vim.api.nvim_win_set_height(State.win.output, height)
    end

    -- ★修正: 最後にフォーカスを戻す処理を schedule で遅延実行する
    -- これにより、ウィンドウ分割処理が完全に終わった後に確実にカーソルが戻る
    vim.schedule(function()
        if return_to and vim.api.nvim_win_is_valid(return_to) then
            vim.api.nvim_set_current_win(return_to)
        end
    end)
end

function UI.close_windows()
    if State.win.preview and vim.api.nvim_win_is_valid(State.win.preview) then 
        vim.api.nvim_win_close(State.win.preview, true) 
    end
    if State.win.output and vim.api.nvim_win_is_valid(State.win.output) then 
        vim.api.nvim_win_close(State.win.output, true) 
    end
    State.win.preview, State.win.output = nil, nil
    State.current_preview_file = nil
end

function UI.open_markdown_preview(filepath)
    if not (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) then return end
    
    -- ★修正1: ウィンドウを移動する「前」に、絶対パスでディレクトリを確定させる
    -- これで、Previewウィンドウがどこに cd していようと関係なくなる
    local abs_filepath = vim.fn.fnamemodify(filepath, ":p")
    local file_dir = vim.fn.fnamemodify(abs_filepath, ":h")
    
    State.current_preview_file = abs_filepath -- 保存も絶対パスで統一

    local cur_win = vim.api.nvim_get_current_win()

    -- 1. Previewウィンドウにフォーカス
    vim.api.nvim_set_current_win(State.win.preview)
    
    -- 2. 確定済みの絶対パスへ lcd
    vim.cmd("lcd " .. file_dir)

    -- 3. ファイルを開く (絶対パスで)
    vim.cmd("edit! " .. abs_filepath)
    
    -- 4. FileType設定
    vim.bo.filetype = "markdown"
    vim.bo.buftype = "" 
    vim.wo.wrap = true

    -- Race Condition防止
    vim.schedule(function()
        if vim.api.nvim_win_is_valid(cur_win) then
            vim.api.nvim_set_current_win(cur_win)
        end
    end)
end

function UI.show_dataframe(data)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    -- ★設定: 見た目のカスタマイズ
    local SEPARATOR = " │ " 
    local PADDING = 1 -- 左右の余白
    
    -- ヘッダー準備
    local headers = { "" } -- Index列用 (空文字)
    for _, c in ipairs(data.columns) do table.insert(headers, tostring(c)) end
    
    -- 幅計算 (バイト数ではなく、見た目の幅 strdisplaywidth を使う)
    local col_widths = {}
    
    -- ヘッダーの幅を初期値にする
    for i, h in ipairs(headers) do 
        col_widths[i] = vim.fn.strdisplaywidth(h) 
    end

    -- データの幅を走査して最大幅を更新
    for i, row in ipairs(data.data) do
        local idx = tostring(data.index[i])
        col_widths[1] = math.max(col_widths[1], vim.fn.strdisplaywidth(idx))
        
        for j, val in ipairs(row) do
            local s = tostring(val)
            col_widths[j+1] = math.max(col_widths[j+1] or 0, vim.fn.strdisplaywidth(s))
        end
    end

    -- パディング関数 (右埋め)
    local function pad_str(s, w) 
        local vis_w = vim.fn.strdisplaywidth(s)
        return string.rep(" ", PADDING) .. s .. string.rep(" ", w - vis_w + PADDING)
    end

    local fmt_lines = {}
    
    -- 1. ヘッダー行作成
    local header_line = ""
    for i, h in ipairs(headers) do 
        header_line = header_line .. pad_str(h, col_widths[i]) .. (i < #headers and SEPARATOR or "")
    end
    table.insert(fmt_lines, header_line)

    -- 2. 区切り線作成
    local sep_line = ""
    for i, w in ipairs(col_widths) do
        -- 文字幅 + 左右パディング分 の線を引く
        local total_w = w + (PADDING * 2)
        sep_line = sep_line .. string.rep("─", total_w) .. (i < #headers and "─┼─" or "")
    end
    table.insert(fmt_lines, sep_line)

    -- 3. データ行作成
    for i, row in ipairs(data.data) do
        local line_str = pad_str(tostring(data.index[i]), col_widths[1]) .. SEPARATOR
        for j, val in ipairs(row) do
            line_str = line_str .. pad_str(tostring(val), col_widths[j+1]) .. (j < #row and SEPARATOR or "")
        end
        table.insert(fmt_lines, line_str)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, fmt_lines)

    -- === ハイライト適用 ===
    
    -- 1行目（ヘッダー）: Title色
    vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    
    -- 2行目（区切り線）: Comment色
    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1)
    
    -- ★ Index列（1列目）を特別扱いしてハイライト
    -- Indexの幅 + パディング + セパレータの左側まで
    local index_col_width = col_widths[1] + (PADDING * 2) 
    
    for i = 2, #fmt_lines - 1 do -- ヘッダーと区切り線を除くデータ行
        -- 行ごとの Index列部分だけを "Statement" (通常は青や黄色) にする
        vim.api.nvim_buf_add_highlight(buf, -1, "Statement", i, 0, index_col_width)
        
        -- 区切り線部分を薄くする ("Comment")
        local current_pos = 0
        for j, w in ipairs(col_widths) do
            current_pos = current_pos + w + (PADDING * 2)
            if j < #col_widths then
                -- セパレータの位置: current_pos から current_pos + #SEPARATOR
                vim.api.nvim_buf_add_highlight(buf, -1, "Comment", i, current_pos, current_pos + #SEPARATOR)
                current_pos = current_pos + #SEPARATOR
            end
        end
    end

    -- Window設定
    local width = math.floor(vim.o.columns * 0.85) -- 少し広めに
    local height = math.floor(vim.o.lines * 0.7)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = width, height = height, row = row, col = col,
        style = "minimal", border = "rounded", title = " " .. data.name .. " ", title_pos = "center"
    })

    -- ★ 使い勝手向上設定
    vim.wo[win].wrap = false       -- 折り返し無効（表が崩れるから）
    vim.wo[win].cursorline = true  -- 現在行をハイライト（横に長いときに必須）
    
    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

function UI.show_variables(vars)
    -- 1. バッファ作成
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    -- 2. 表示内容の整形 (Markdownの表形式っぽくする)
    local lines = { "VARIABLE             TYPE             VALUE/INFO", "------------------------------------------------------------" }
    
    for _, v in ipairs(vars) do
        -- 固定長フォーマット (Name:20, Type:16, Info:残り)
        local name = v.name .. string.rep(" ", 20 - #v.name)
        local type_name = v.type .. string.rep(" ", 16 - #v.type)
        table.insert(lines, name .. type_name .. v.info)
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- 3. ハイライトの設定 (簡易シンタックス)
    -- 1行目を特別色に
    vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, -1, "Comment", 1, 0, -1) -- 区切り線

    -- 4. フローティングウィンドウの計算
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Jukit Variables ",
        title_pos = "center"
    }

    -- 5. ウィンドウを開く
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    
    -- 6. 閉じるためのキーマップ (q または Esc)
    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

-- === カーネル通信・実行 (Kernel & Execution) ===
local function on_stdout(chan_id, data, name)
    if not data then return end
    for _, line in ipairs(data) do
        if line ~= "" then
            local ok, msg = pcall(vim.fn.json_decode, line)
            if ok and msg then
                vim.schedule(function()
                    if msg.type == "stream" then
                        UI.append_stream_text(msg.text)
                    elseif msg.type == "image_saved" then
                        UI.append_to_repl("[Image Created]: " .. vim.fn.fnamemodify(msg.path, ":t"), "Special")
                    elseif msg.type == "result_ready" then
                        UI.append_to_repl("-> Done: " .. msg.cell_id, "Comment")
                        State.current_preview_file = nil 
                        UI.open_markdown_preview(msg.file)
                        
                        local target_buf = State.cell_buf_map[msg.cell_id]
                        if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
                            -- ★ 通知判定: 一定時間以上かかったらOS通知
                            local start_t = State.cell_start_time[msg.cell_id]
                            if start_t and (os.time() - start_t) >= M.config.notify_threshold then
                                send_notification("Calculation " .. msg.cell_id .. " Finished!")
                            end

                            -- ★ エラー診断表示 (インライン・エラー)
                            vim.api.nvim_buf_clear_namespace(target_buf, State.diag_ns, 0, -1)
                            if msg.error then
                                set_cell_status(target_buf, msg.cell_id, "error", "✘ Error")
                                local start_line = State.cell_start_line[msg.cell_id] or 1
                                -- Pythonのエラー行は相対的なので、セルの開始位置を足す
                                -- Luaは0-indexなので、(start_line - 1) + (error_line - 1)
                                local target_line = (start_line - 1) + (msg.error.line - 1)
                                
                                vim.diagnostic.set(State.diag_ns, target_buf, {{
                                    lnum = target_line,
                                    col = 0,
                                    message = msg.error.msg,
                                    severity = vim.diagnostic.severity.ERROR,
                                    source = "Jukit",
                                }})
                            else
                                set_cell_status(target_buf, msg.cell_id, "done", " Done")
                            end
                        end
                        -- クリーンアップ
                        State.cell_buf_map[msg.cell_id] = nil
                        State.cell_start_time[msg.cell_id] = nil
                        State.cell_start_line[msg.cell_id] = nil

                    elseif msg.type == "variable_list" then
                        UI.show_variables(msg.variables)
                    elseif msg.type == "dataframe_data" then
                        UI.show_dataframe(msg) -- ★ DataFrame表示
                    elseif msg.type == "input_request" then
                        UI.append_to_repl("[Input Requested]: " .. msg.prompt, "Special")
                        vim.ui.input({ prompt = msg.prompt }, function(input)
                            local value = input or ""
                            UI.append_to_repl(value)
                            if State.job_id then
                                local reply = vim.fn.json_encode({ command = "input_reply", value = value })
                                vim.fn.chansend(State.job_id, reply .. "\n")
                            end
                        end)
                    end
                end)
            end
        end
    end
end

function M.start_kernel()
    if State.job_id then return end
    local script = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h") .. "/lua/jukit/kernel.py"
    local cmd = vim.split(M.config.python_interpreter, " ")
    table.insert(cmd, script)
    
    State.job_id = vim.fn.jobstart(cmd, {
        on_stdout = on_stdout,
        on_stderr = on_stdout,
        stdout_buffered = false,
        on_exit = function() State.job_id = nil end
    })
    UI.append_to_repl("[Jukit Kernel Started]")
    vim.defer_fn(function() M.clean_stale_cache() end, 500)
end

function M.restart_kernel()
    if State.job_id then vim.fn.jobstop(State.job_id); State.job_id = nil end
    UI.append_to_repl("[Kernel Restarting...]", "WarningMsg")
    M.start_kernel()
end

local function send_payload(code, cell_id, filename)
    if not State.job_id then M.start_kernel() end
    local current_buf = vim.api.nvim_get_current_buf()

    -- ★ ステート保存: バッファID, 開始時間, 開始行
    State.cell_buf_map[cell_id] = current_buf
    State.cell_start_time[cell_id] = os.time()
    
    -- 開始行を検索して保存（エラー診断で位置特定するため）
    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    for i, line in ipairs(lines) do
        if line:find('id="' .. cell_id .. '"', 1, true) then
            -- # %% の次の行がコード開始行
            State.cell_start_line[cell_id] = i + 1 
            break
        end
    end

    -- 実行前に既存の診断とステータスをクリア
    vim.api.nvim_buf_clear_namespace(current_buf, State.diag_ns, 0, -1)

    State.cell_buf_map[cell_id] = current_buf
    set_cell_status(current_buf, cell_id, "running", " Running...")
    
    UI.append_to_repl({"In [" .. cell_id .. "]:"}, "Type")
    UI.append_to_repl({"In [" .. cell_id .. "]:"}, "Type")
    
    local code_lines = vim.split(code, "\n")
    local indented = {}
    for _, l in ipairs(code_lines) do table.insert(indented, "    " .. l) end
    UI.append_to_repl(indented)
    UI.append_to_repl({""})

    local msg = vim.fn.json_encode({
        command = "execute", code = code, cell_id = cell_id, filename = filename
    })
    vim.fn.chansend(State.job_id, msg .. "\n")
end

function M.send_cell()
    local src_win = vim.api.nvim_get_current_win()
    UI.open_windows(src_win)
    vim.api.nvim_set_current_win(src_win) -- 念のため

    local s, e = Utils.get_cell_range()
    UI.flash_range(s, e)
    
    local lines = vim.api.nvim_buf_get_lines(0, s-1, e, false)
    if #lines > 0 and lines[1]:match("^# %%%%") then table.remove(lines, 1) end
    
    local id = Utils.get_current_cell_id(s)
    local fn = vim.fn.expand("%:t")
    if fn == "" then fn = "untitled" end
    
    send_payload(table.concat(lines, "\n"), id, fn)
end

function M.send_selection()
    local src_win = vim.api.nvim_get_current_win()
    UI.open_windows(src_win)
    vim.api.nvim_set_current_win(src_win)

    local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
    local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))
    local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)
    
    if #lines == 0 then return end
    UI.flash_range(csrow, cerow)
    
    local id = Utils.get_current_cell_id(csrow)
    local fn = vim.fn.expand("%:t")
    if fn == "" then fn = "untitled" end
    
    send_payload(table.concat(lines, "\n"), id, fn)
end

function M.run_all_cells()
    local src_win = vim.api.nvim_get_current_win()
    UI.open_windows(src_win)
    vim.api.nvim_set_current_win(src_win)
    
    if not State.job_id then M.start_kernel() end
    local fn = vim.fn.expand("%:t")
    if fn == "" then fn = "untitled" end
    
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local blk, bid, is_code = {}, "scratchpad", true
    
    for i, line in ipairs(lines) do
        if line:match("^# %%%%") then
            if #blk > 0 and is_code then send_payload(table.concat(blk, "\n"), bid, fn) end
            blk, bid = {}, Utils.ensure_cell_id(i, line)
            is_code = not line:lower():match("^# %%%%+%s*%[markdown%]")
        else
            if is_code then table.insert(blk, line) end
        end
    end
    if #blk > 0 and is_code then send_payload(table.concat(blk, "\n"), bid, fn) end
end

function M.view_dataframe(args)
    if not State.job_id then return vim.notify("Kernel not started", vim.log.levels.WARN) end
    -- 引数 (変数名) を取得。なければカーソル下の単語
    local var_name = args.args
    if var_name == "" then var_name = vim.fn.expand("<cword>") end
    
    local msg = vim.fn.json_encode({ command = "view_dataframe", name = var_name })
    vim.fn.chansend(State.job_id, msg .. "\n")
end

function M.clean_stale_cache()
    if not State.job_id then return end
    local filename = vim.fn.expand("%:t")
    if filename == "" then return end
    
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local valid_ids = {}
    for _, line in ipairs(lines) do
        local id = line:match("id=\"([%w%-_]+)\"")
        if id then table.insert(valid_ids, id) end
    end
    
    local msg = vim.fn.json_encode({
        command = "clean_cache",
        filename = filename,
        valid_ids = valid_ids
    })
    vim.fn.chansend(State.job_id, msg .. "\n")
end

function M.check_cursor_cell()
    if not State.job_id then return end
    
    vim.schedule(function()
        local cell_id = Utils.get_current_cell_id()
        local filename = vim.fn.expand("%:t")
        if filename == "" then filename = "scratchpad" end
        
        local cache_dir = ".jukit_cache/" .. filename
        local rel_path = cache_dir .. "/" .. cell_id .. ".md"
        
        -- ★修正2: 比較や引数渡しの前に、ここで絶対パスに変換しておく
        local md_path = vim.fn.fnamemodify(rel_path, ":p")
        
        -- ファイルが変わったときのみ更新 (絶対パス同士で比較)
        if State.current_preview_file ~= md_path and vim.fn.filereadable(md_path) == 1 then
            UI.open_markdown_preview(md_path)
        end
    end)
end

function M.show_variables()
    if not State.job_id then return vim.notify("Kernel not started", vim.log.levels.WARN) end
    
    local msg = vim.fn.json_encode({ command = "get_variables" })
    vim.fn.chansend(State.job_id, msg .. "\n")
end

function M.goto_next_cell()
    local cursor = vim.fn.line(".")
    local total = vim.api.nvim_buf_line_count(0)
    
    -- カーソル行の次から下へ検索
    for i = cursor + 1, total do
        local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
        if line:match("^# %%%%") then
            -- 移動 & 画面中央へ
            vim.api.nvim_win_set_cursor(0, {i, 0})
            vim.cmd("normal! zz")
            
            -- 移動先をハイライトしてアピール
            local s, e = Utils.get_cell_range(i)
            UI.flash_range(s, e)
            return
        end
    end
    vim.notify("No next cell found", vim.log.levels.INFO)
end

function M.goto_prev_cell()
    local cursor = vim.fn.line(".")
    
    -- カーソル行の前から上へ検索
    for i = cursor - 1, 1, -1 do
        local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
        if line:match("^# %%%%") then
            -- 移動 & 画面中央へ
            vim.api.nvim_win_set_cursor(0, {i, 0})
            vim.cmd("normal! zz")
            
            -- 移動先をハイライト
            local s, e = Utils.get_cell_range(i)
            UI.flash_range(s, e)
            return
        end
    end
    vim.notify("No previous cell found", vim.log.levels.INFO)
end

-- === セル操作ユーティリティ ===

function M.insert_cell_below()
    local _, e = Utils.get_cell_range()
    local new_id = Utils.generate_id()
    local lines = { "", "# %% id=\"" .. new_id .. "\"", "" }
    
    -- 現在のセルの終了行の下に挿入
    vim.api.nvim_buf_set_lines(0, e, e, false, lines)
    
    -- カーソルを新しいセルに移動
    vim.api.nvim_win_set_cursor(0, {e + 3, 0})
    vim.cmd("startinsert") -- そのまま入力モードへ
end

function M.insert_cell_above()
    local s, _ = Utils.get_cell_range()
    local new_id = Utils.generate_id()
    local lines = { "# %% id=\"" .. new_id .. "\"", "", "" }
    
    -- 現在のセルの開始行の上に挿入
    vim.api.nvim_buf_set_lines(0, s - 1, s - 1, false, lines)
    
    -- カーソルを新しいセルに移動
    vim.api.nvim_win_set_cursor(0, {s + 1, 0})
    vim.cmd("startinsert")
end

function M.merge_cell_below()
    local _, e = Utils.get_cell_range()
    local total = vim.api.nvim_buf_line_count(0)
    
    if e >= total then return vim.notify("No cell below", vim.log.levels.WARN) end
    
    -- 下のセルの境界線を探す（eの次は必ず境界のはずだが念のため）
    local line = vim.api.nvim_buf_get_lines(0, e, e + 1, false)[1]
    if line:match("^# %%%%") then
        -- 境界線を削除
        vim.api.nvim_buf_set_lines(0, e, e + 1, false, {})
        vim.notify("Cells merged", vim.log.levels.INFO)
    else
        vim.notify("Could not find cell boundary below", vim.log.levels.WARN)
    end
end

function M.clear_repl()
    if State.buf.output and vim.api.nvim_buf_is_valid(State.buf.output) then
        vim.api.nvim_buf_set_lines(State.buf.output, 0, -1, false, {"[Jukit Console Cleared]"})
    end
end

function M.toggle_windows()
    if (State.win.preview and vim.api.nvim_win_is_valid(State.win.preview)) or 
       (State.win.output and vim.api.nvim_win_is_valid(State.win.output)) then
        UI.close_windows()
    else
        UI.open_windows()
    end
end

-- === セットアップ ===
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", default_config, opts or {})
    
    vim.api.nvim_create_user_command("JukitStart", M.start_kernel, {})
    vim.api.nvim_create_user_command("JukitRun", M.send_cell, {})
    vim.api.nvim_create_user_command("JukitSendSelection", M.send_selection, { range = true })
    vim.api.nvim_create_user_command("JukitRunAll", M.run_all_cells, {})
    vim.api.nvim_create_user_command("JukitRestart", M.restart_kernel, {})
    vim.api.nvim_create_user_command("JukitOpen", function() UI.open_windows() end, {})
    vim.api.nvim_create_user_command("JukitToggle", M.toggle_windows, {})
    vim.api.nvim_create_user_command("JukitClean", M.clean_stale_cache, {})
    vim.api.nvim_create_user_command("JukitVars", M.show_variables, {})

    vim.api.nvim_create_user_command("JukitNextCell", M.goto_next_cell, {})
    vim.api.nvim_create_user_command("JukitPrevCell", M.goto_prev_cell, {})

    vim.api.nvim_create_user_command("JukitNewCellBelow", M.insert_cell_below, {})
    vim.api.nvim_create_user_command("JukitNewCellAbove", M.insert_cell_above, {})
    vim.api.nvim_create_user_command("JukitMergeBelow", M.merge_cell_below, {})
    
    vim.api.nvim_create_user_command("JukitClear", M.clear_repl, {})

    vim.api.nvim_create_user_command("JukitView", M.view_dataframe, { nargs = "?" })
    
    -- ★ 追加: 折りたたみ設定 (Fold)
    vim.opt.foldmethod = "expr"
    vim.opt.foldexpr = "getline(v:lnum)=~'^#\\ %%'?'0':'1'" -- # %% の行はレベル0(見出し)、他はレベル1
    vim.opt.foldlevel = 99 -- 最初は開いておく
    
    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = "*",
        callback = function() 
            if vim.bo.filetype == "python" then M.check_cursor_cell() end 
        end
    })
end

return M
