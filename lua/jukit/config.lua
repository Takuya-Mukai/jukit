local M = {}

M.defaults = {
    preview_width_percent = 40,
    repl_height_percent = 30,
    preview_image_ratio = 0.6,
    repl_image_ratio = 0.3,
    flash_highlight_group = "Visual",
    flash_duration = 300,
    python_interpreter = "python3", 
    notify_threshold = 10,
}

-- 現在の設定（setupで上書きされる）
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
