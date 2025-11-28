local M = {}
local job_id = nil
local output_buf = nil
local output_win = nil
local preview_buf = nil
local preview_win = nil
local stdout_buffer = {}

-- 現在表示しているセルIDを記憶（無駄な再描画を防ぐため）
M.last_previewed_id = nil

M.repl_images = {} 
M.preview_images = {}

-- === ユーティリティ ===

local function generate_id()
    math.randomseed(os.time())
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    local id = ""
    for i = 1, 8 do
        local rand = math.random(#chars)
        id = id .. string.sub(chars, rand, rand)
    end
    return id
end

local function get_cell_id(line_num)
    local line
    if line_num then
        local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)
        if #lines > 0 then line = lines[1] else line = "" end
    else
        line = vim.api.nvim_get_current_line()
    end
    
    local existing_id = line:match("id=\"([%w%-_]+)\"")
    if existing_id then
        return existing_id
    else
        local current_lnum = line_num or vim.fn.line(".")
        local found_id = nil
        -- 上方向にセルマーカーを探索
        for l = current_lnum, 1, -1 do
            local l_content = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1]
            local mid = l_content:match("id=\"([%w%-_]+)\"")
            if mid then
                found_id = mid
                break
            end
            if l_content:match("^# %%%%") then break end
        end

        if found_id then
            return found_id
        else
            -- マーカーがない、またはIDがない場合は新規生成（ただしカーソル行にマーカーがある時のみ）
            local id = generate_id()
            if line:match("^# %%%%") then
                local new_line = line .. " id=\"" .. id .. "\""
                if line_num then
                    vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {new_line})
                else
                    vim.api.nvim_set_current_line(new_line)
                end
                return id
            else
                return "scratchpad"
            end
        end
    end
end

-- === 描画ヘルパー ===

local function append_text(buf, win, text_lines, highlight_group)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, text_lines)
    
    if highlight_group then
        local last_line = vim.api.nvim_buf_line_count(buf)
        for i = 0, #text_lines - 1 do
            vim.api.nvim_buf_add_highlight(buf, -1, highlight_group, last_line - #text_lines + i, 0, -1)
        end
    end

    if win and vim.api.nvim_win_is_valid(win) then
        local count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(win, {count, 0})
    end
end

-- 画像描画 (物理パディング方式)
local function append_image(buf, win, image_path, opts, store_table)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    
    opts = opts or {}
    local img_height = opts.height or 15
    local img_width = opts.width or 50

    -- 物理的な空行を追加して場所を確保
    local empty_lines = {}
    for i = 1, img_height do
        table.insert(empty_lines, "")
    end
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, empty_lines)
    
    local current_total_lines = vim.api.nvim_buf_line_count(buf)
    local target_line_index = current_total_lines - img_height

    local ok_img, image = pcall(require, "image")
    if ok_img then
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end

            local img = image.from_file(image_path, {
                buffer = buf,
                window = win,
                with_virtual_padding = false, -- 物理空行があるのでFalse
                inline = true,
                x = 0,
                y = target_line_index,
                width = img_width,
                height = img_height,
            })
            
            if img then 
                img:render() 
                if store_table then
                    table.insert(store_table, img)
                end
            end
        end)
    else
        vim.api.nvim_buf_set_lines(buf, target_line_index, target_line_index + 1, false, {"[Image]: " .. image_path})
    end
    
    if win and vim.api.nvim_win_is_valid(win) then
        local count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_win_set_cursor(win, {count, 0})
    end
end

-- === ★ Previewウィンドウの更新（完全クリア & キャッシュ読込） ===

function M.render_preview(cell_id)
    if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then return end

    -- 1. まずバッファを完全にクリア
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
    
    -- 2. 既存の画像リストもクリア (image.nvimのクリアメソッドがあれば呼ぶとなお良い)
    for _, img in ipairs(M.preview_images) do
        if img.clear then img:clear() end
    end
    M.preview_images = {}
    
    -- 3. 表示中のIDを更新
    M.last_previewed_id = cell_id

    -- ヘッダー表示
    append_text(preview_buf, preview_win, {"=== Output for Cell [" .. cell_id .. "] ===", ""}, "Title")

    -- 4. キャッシュファイルを探す
    local filename = vim.fn.expand("%:t")
    if filename == "" then filename = "scratchpad" end
    local cache_dir = ".jukit_cache/" .. filename
    
    local pattern = cache_dir .. "/" .. cell_id .. "_*"
    local files_str = vim.fn.glob(pattern)
    
    if files_str == "" then
        append_text(preview_buf, preview_win, {"(No output cache found)"}, "Comment")
        return
    end

    local files = vim.split(files_str, "\n", { trimempty = true })
    table.sort(files)

    -- 5. 順番に描画
    for _, filepath in ipairs(files) do
        if filepath:match("%.txt$") then
            local f = io.open(filepath, "r")
            if f then
                local content = f:read("*a")
                f:close()
                if content and content ~= "" then
                    content = content:gsub("\r\n", "\n")
                    local lines = vim.split(content, "\n")
                    if lines[#lines] == "" then table.remove(lines, #lines) end
                    append_text(preview_buf, preview_win, lines)
                end
            end
        elseif filepath:match("%.png$") then
            append_image(preview_buf, preview_win, filepath, {height = 20}, M.preview_images)
        end
    end
end

-- === ハンドラ (リアルタイム更新) ===

local function on_stdout(chan_id, data, name)
    if not data then return end
    if #stdout_buffer > 0 then
        data[1] = table.concat(stdout_buffer) .. data[1]
        stdout_buffer = {}
    end
    if #data > 0 then
        stdout_buffer = { table.remove(data, #data) }
    end

    for _, line in ipairs(data) do
        if line ~= "" then
            local ok, msg = pcall(vim.fn.json_decode, line)
            if ok and msg then
                vim.schedule(function()
                    local cell_id = msg.cell_id or "unknown"
                    
                    -- A. REPLへは常にログ追記
                    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
                        if msg.type == "text_file" then
                            local f = io.open(msg.payload, "r")
                            if f then
                                local content = f:read("*a")
                                f:close()
                                if content and content ~= "" then
                                    content = content:gsub("\r\n", "\n")
                                    local lines = vim.split(content, "\n")
                                    if lines[#lines] == "" then table.remove(lines, #lines) end
                                    
                                    append_text(output_buf, output_win, {"Out [" .. cell_id .. "]:"}, "Comment")
                                    append_text(output_buf, output_win, lines)
                                end
                            end
                        elseif msg.type == "image_file" then
                            append_text(output_buf, output_win, {"Out [" .. cell_id .. "]: (Image)"}, "Comment")
                            append_image(output_buf, output_win, msg.payload, {height=10}, M.repl_images)
                        elseif msg.type == "error" then
                            local lines = vim.split(msg.payload, "\n")
                            table.insert(lines, 1, "--- ERROR ---")
                            append_text(output_buf, output_win, lines, "ErrorMsg")
                        end
                    end

                    -- B. Previewのリアルタイム更新
                    -- もし今見ているセルが実行中のセルなら、その都度再描画して更新を反映させる
                    local current_cursor_cell_id = get_cell_id()
                    if current_cursor_cell_id == cell_id then
                        M.render_preview(cell_id)
                    end
                end)
            end
        end
    end
end

-- === ★ 自動更新ロジック (CursorHold) ===

function M.check_cursor_cell()
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then return end
    
    local current_id = get_cell_id()
    
    -- 前回表示したIDと違う場合のみ更新（チラつき防止）
    if M.last_previewed_id ~= current_id then
        M.render_preview(current_id)
    end
end

-- === コード送信 ===

function M.send_cell()
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then M.init_windows() end
    if not job_id then M.start_kernel() end
    
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local total_lines = vim.api.nvim_buf_line_count(0)
    
    local start_line = cursor_line
    while start_line > 1 do
        local l = vim.api.nvim_buf_get_lines(0, start_line - 1, start_line, false)[1]
        if l:match("^# %%%%") then break end
        start_line = start_line - 1
    end
    local end_line = cursor_line
    while end_line < total_lines do
        local l = vim.api.nvim_buf_get_lines(0, end_line, end_line + 1, false)[1]
        if l:match("^# %%%%") then break end
        end_line = end_line + 1
    end
    
    local cell_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    if #cell_lines > 0 and cell_lines[1]:match("^# %%%%") then
        table.remove(cell_lines, 1)
    end
    
    local cell_id = get_cell_id(start_line)
    
    -- 実行開始時は、Previewに「実行中...」と出す
    if preview_buf then
        -- ここでも一旦クリア
        vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, {})
        M.preview_images = {}
        append_text(preview_buf, preview_win, {"", "--- Processing Cell [" .. cell_id .. "]... ---"}, "Special")
    end

    local code = table.concat(cell_lines, "\n")
    local filename = vim.fn.expand("%:t")
    if filename == "" then filename = "untitled" end

    -- REPLログ
    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
        local log_lines = {"", "In [" .. cell_id .. "]:"}
        for _, l in ipairs(cell_lines) do table.insert(log_lines, "    " .. l) end
        append_text(output_buf, output_win, log_lines)
    end

    local msg = vim.fn.json_encode({
        command = "execute",
        code = code,
        cell_id = cell_id,
        filename = filename
    })
    vim.fn.chansend(job_id, msg .. "\n")
end

-- === 初期化 ===

function M.init_windows()
    local code_win = vim.api.nvim_get_current_win()
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
        vim.cmd("vsplit")
        vim.cmd("wincmd L")
        preview_win = vim.api.nvim_get_current_win()
        preview_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(preview_buf, "buftype", "nofile")
        vim.api.nvim_buf_set_name(preview_buf, "JukitPreview")
        vim.api.nvim_win_set_buf(preview_win, preview_buf)
    end
    vim.api.nvim_set_current_win(code_win)
    if not (output_win and vim.api.nvim_win_is_valid(output_win)) then
        vim.cmd("split")
        vim.cmd("wincmd j")
        vim.api.nvim_win_set_height(0, 15) 
        output_win = vim.api.nvim_get_current_win()
        output_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(output_buf, "buftype", "nofile")
        vim.api.nvim_buf_set_name(output_buf, "JukitConsole")
        vim.api.nvim_win_set_buf(output_win, output_buf)
        vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {"[Jukit Kernel Console Ready]"})
    end
    vim.api.nvim_set_current_win(code_win)
end

function M.clean_stale_cache()
    if not job_id then return end
    
    local filename = vim.fn.expand("%:t")
    if filename == "" then return end
    
    -- バッファ全体から id="..." を抽出
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local valid_ids = {}
    
    for _, line in ipairs(lines) do
        local id = line:match("id=\"([%w%-_]+)\"")
        if id then
            table.insert(valid_ids, id)
        end
    end
    
    -- Python側へ clean_cache コマンドを送信
    local msg = vim.fn.json_encode({
        command = "clean_cache",
        filename = filename,
        valid_ids = valid_ids
    })
    vim.fn.chansend(job_id, msg .. "\n")
end

function M.start_kernel()
    if job_id then return end
    M.repl_images = {}
    M.preview_images = {}
    
    local source = debug.getinfo(1).source:sub(2)
    local root = vim.fn.fnamemodify(source, ":h:h:h")
    local script_path = root .. "/lua/jukit/kernel.py"
    job_id = vim.fn.jobstart({"python3", script_path}, {
        on_stdout = on_stdout,
        on_stderr = on_stdout,
        stdout_buffered = false,
        -- カーネル起動直後にキャッシュのクリーンアップを実行
        on_exit = function() job_id = nil end
    })
    
    if output_buf and vim.api.nvim_buf_is_valid(output_buf) then
         vim.api.nvim_buf_set_lines(output_buf, -1, -1, false, {"Kernel Job ID: " .. job_id})
    end

    -- ★ カーネル起動時に、現在のファイルの不要キャッシュを掃除
    -- 少し待ってから送る（プロセス起動待ち）
    vim.defer_fn(function()
        M.clean_stale_cache()
    end, 500)
end

function M.setup(opts)
    vim.api.nvim_create_user_command("JukitStart", M.start_kernel, {})
    vim.api.nvim_create_user_command("JukitRun", M.send_cell, {})
    vim.api.nvim_create_user_command("JukitInit", M.init_windows, {})

    -- ★ 自動更新 (CursorHold)
    -- カーソルが停止した時に発火します。反応を良くするには set updatetime=300 推奨。
    vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI"}, {
        pattern = "*",
        callback = function()
            if vim.bo.filetype == "python" then
                -- Jukitが動いていない時でもキャッシュ表示したい場合は job_id チェックを外してください
                if job_id then
                    M.check_cursor_cell()
                end
            end
        end
    })
end

return M
