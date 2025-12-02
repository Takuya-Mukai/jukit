package.path = package.path .. ";lua/?.lua"

-- Mock vim.lsp.handlers BEFORE requiring the module
vim.lsp = vim.lsp or {}
vim.lsp.handlers = vim.lsp.handlers or {}
local original_handler_called = false
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
    original_handler_called = true
    return result.diagnostics
end

local Diagnostics = require("jovian.diagnostics")
local Config = require("jovian.config")

-- Setup
Config.setup({})
Diagnostics.setup()

-- Mock buffer and content
local bufnr = vim.api.nvim_create_buf(false, true)
vim.bo[bufnr].filetype = "python"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "print('hello')",
    "%timeit sum(range(100))",
    "!ls -la",
    "def foo():",
    "    pass"
})

-- Mock URI
local uri = "file:///tmp/test.py"
-- Mock vim.uri_to_bufnr (simple mock for this test)
vim.uri_to_bufnr = function(u)
    if u == uri then return bufnr end
    return -1
end

-- Create diagnostics
local diagnostics = {
    {
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } },
        severity = vim.diagnostic.severity.ERROR,
        message = "Syntax error", -- Should keep (line 1: print)
    },
    {
        range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 1 } },
        severity = vim.diagnostic.severity.ERROR,
        message = "Syntax error", -- Should remove (line 2: %timeit)
    },
    {
        range = { start = { line = 2, character = 0 }, ["end"] = { line = 2, character = 1 } },
        severity = vim.diagnostic.severity.ERROR,
        message = "Syntax error", -- Should remove (line 3: !ls)
    },
    {
        range = { start = { line = 3, character = 0 }, ["end"] = { line = 3, character = 3 } },
        severity = vim.diagnostic.severity.HINT,
        message = "Hint", -- Should keep (line 4: def)
    },
}

-- Run handler
local handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
local result = { uri = uri, diagnostics = diagnostics }
local filtered = handler(nil, result, {}, {})

-- Verify
print("Original handler called: " .. tostring(original_handler_called))
print("Filtered count: " .. #filtered)

for i, d in ipairs(filtered) do
    print("Diag " .. i .. ": Line " .. d.range.start.line .. " - " .. d.message)
end

if #filtered ~= 2 then
    error("Expected 2 diagnostics, got " .. #filtered)
end

if filtered[1].range.start.line ~= 0 then error("Expected line 0") end
if filtered[2].range.start.line ~= 3 then error("Expected line 3") end

print("SUCCESS")
