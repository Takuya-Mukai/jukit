local M = {}

M.job_id = nil
M.term_chan = nil

M.buf = { output = nil, preview = nil }
M.win = { output = nil, preview = nil }

-- 名前空間 (Highlight Namespace)
M.hl_ns = vim.api.nvim_create_namespace("JovianCellHighlight")
M.status_ns = vim.api.nvim_create_namespace("JovianStatus")
M.diag_ns = vim.api.nvim_create_namespace("JovianDiagnostics")

M.current_preview_file = nil

-- 各種マッピング
M.cell_buf_map = {}      -- { cell_id: bufnr }
M.cell_start_time = {}   -- { cell_id: timestamp }
M.cell_start_line = {}   -- { cell_id: line_num }

return M
