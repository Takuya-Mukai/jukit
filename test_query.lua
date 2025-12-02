-- Add jovian_queries to runtime path
vim.opt.rtp:prepend("jovian_queries")

-- Register predicate manually for the test script context (since init.lua isn't fully loaded)
local ok, err = pcall(function()
    vim.treesitter.query.add_predicate("same-line?", function(match, pattern, bufnr, predicate)
        local node1 = match[predicate[2]]
        local node2 = match[predicate[3]]
        if not node1 or not node2 then 
            print("same-line?: Missing nodes")
            return false 
        end
        if type(node1) == "table" then node1 = node1[1] end
        if type(node2) == "table" then node2 = node2[1] end
        
        local r1, _, _, _ = node1:range()
        local r2, _, _, _ = node2:range()
        print("same-line?: " .. r1 .. " vs " .. r2)
        return r1 == r2
    end, true)
end)

local source = [[
!ls --color=always
!ls a b
]]
local parser = vim.treesitter.get_string_parser(source, "python")
local tree = parser:parse()[1]
local root = tree:root()

-- Test loading from file
local query = vim.treesitter.query.get("python", "highlights")

if not query then
    print("Error: Could not load highlights query")
    return
end

local captures = {}
for id, node, metadata in query:iter_captures(root, source, 0, -1) do
    local name = query.captures[id]
    local text = vim.treesitter.get_node_text(node, source)
    if name == "function.macro" then
        print("Capture: " .. text .. " (" .. node:type() .. ")")
        table.insert(captures, text)
    end
end

-- Expected captures:
-- !ls --color=always
--   ERROR children: !l, s --color, =
--   Sibling: always
-- !ls a b
--   ERROR children: !l, s, a
--   Sibling: b

local expected_patterns = {
    "!l",
    "s %-%-color",
    "=",
    "always",
    "!l",
    "s",
    "a",
    "b"
}

local found_count = 0
for _, cap in ipairs(captures) do
    print("Capture: " .. cap)
    for _, pat in ipairs(expected_patterns) do
        if cap:match(pat) then
            found_count = found_count + 1
        end
    end
end

if found_count >= 4 then
    print("SUCCESS: Found expected captures")
else
    print("FAILURE: Found " .. found_count .. " expected captures")
end
