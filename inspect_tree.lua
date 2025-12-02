local parser = vim.treesitter.get_string_parser([[
%timeit sum(range(100))
!ls -la
a = 1
]], "python")
local tree = parser:parse()[1]
local root = tree:root()

local function print_node(node, indent)
    local type = node:type()
    local s, sc, e, ec = node:range()
    local text = vim.treesitter.get_node_text(node, [[
%timeit sum(range(100))
!ls -la
a = 1
]])
    print(string.rep("  ", indent) .. type .. " [" .. s .. ":" .. sc .. " - " .. e .. ":" .. ec .. "] " .. (text:gsub("\n", "\\n")))
    
    for child in node:iter_children() do
        print_node(child, indent + 1)
    end
end

print_node(root, 0)
