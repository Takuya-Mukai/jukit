local M = {}

function M.generate_id()
    math.randomseed(os.time())
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    local id = ""
    for i = 1, 8 do
        local rand = math.random(#chars)
        id = id .. string.sub(chars, rand, rand)
    end
    return id
end

function M.get_cell_range(lnum)
    local cursor = lnum or vim.fn.line(".")
    local total = vim.api.nvim_buf_line_count(0)
    local s, e = cursor, cursor
    while s > 1 do
        local line = vim.api.nvim_buf_get_lines(0, s - 1, s, false)[1]
        if line:match("^# %%%%") then break end
        s = s - 1
    end
    while e < total do
        local line = vim.api.nvim_buf_get_lines(0, e, e + 1, false)[1]
        if line:match("^# %%%%") then break end
        e = e + 1
    end
    return s, e
end

function M.ensure_cell_id(line_num, line_content)
    local id = line_content:match("id=\"([%w%-_]+)\"")
    if id then return id end
    id = M.generate_id()
    if line_content:match("^# %%%%") then
        local new_line = line_content .. " id=\"" .. id .. "\""
        vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {new_line})
    end
    return id
end

function M.get_current_cell_id(lnum)
    local s, _ = M.get_cell_range(lnum)
    local lines = vim.api.nvim_buf_get_lines(0, s - 1, s, false)
    local line = lines[1] or ""
    local id = line:match("id=\"([%w%-_]+)\"")
    if id then return id end
    if line:match("^# %%%%") then return M.ensure_cell_id(s, line) end
    return "scratchpad"
end

return M
