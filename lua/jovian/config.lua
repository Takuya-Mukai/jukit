local M = {}

M.defaults = {
    -- UI
    preview_width_percent = 35,
    repl_height_percent = 30,
    preview_image_ratio = 0.3,
    repl_image_ratio = 0.3,
    
    -- Visuals
    flash_highlight_group = "Visual",
    flash_duration = 300,
    
    -- Python Environment
    python_interpreter = "python3", 
    
    -- ★ 追加: SSH Remote Settings
    -- 例: "user@192.168.1.10" または nil (ローカル)
    ssh_host = nil, 
    ssh_python = "python3", -- リモート側のPythonコマンド
    
    -- Behavior
    notify_threshold = 10,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
