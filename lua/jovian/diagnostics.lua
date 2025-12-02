local M = {}
local Config = require("jovian.config")

-- Store the original handler to fallback to
local original_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]

-- Function to filter diagnostics
local function filter_diagnostics(err, result, ctx, config)
    if not result or not result.diagnostics then
        return original_handler(err, result, ctx, config)
    end

    -- Only filter if enabled and filetype is python
    -- Note: ctx.bufnr might not be reliable if the buffer is not loaded, 
    -- but usually publishDiagnostics comes for a specific URI.
    local uri = result.uri
    local bufnr = vim.uri_to_bufnr(uri)
    
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return original_handler(err, result, ctx, config)
    end

    if vim.bo[bufnr].filetype ~= "python" then
        return original_handler(err, result, ctx, config)
    end

    if not Config.options.suppress_magic_command_errors then
        return original_handler(err, result, ctx, config)
    end

    local filtered_diagnostics = {}
    for _, diagnostic in ipairs(result.diagnostics) do
        local keep = true
        
        -- Check if it's a syntax error (usually severity 1)
        -- We can be more aggressive and filter any error on magic lines
        if diagnostic.severity == vim.diagnostic.severity.ERROR then
            local lnum = diagnostic.range.start.line
            -- Get the line content
            local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
            
            if line then
                -- Check for magic commands
                local trimmed = line:match("^%s*(.*)")
                if trimmed and (trimmed:match("^%%") or trimmed:match("^!")) then
                    keep = false
                end
            end
        end

        if keep then
            table.insert(filtered_diagnostics, diagnostic)
        end
    end

    result.diagnostics = filtered_diagnostics
    return original_handler(err, result, ctx, config)
end

function M.setup()
    -- Override the global handler
    -- This is a bit invasive, but standard for this kind of feature
    vim.lsp.handlers["textDocument/publishDiagnostics"] = filter_diagnostics
end

return M
