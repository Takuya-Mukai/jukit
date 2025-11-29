vim.opt.rtp:prepend(".")
local UI = require("jovian.ui")

-- Mock vim.NIL if not available (older neovim versions might behave differently, but let's assume standard)
local NIL = vim.NIL or vim.v.null

print("Reproducing JovianDoc Error...")

-- Case 1: definition is vim.NIL
local data_nil_def = {
    name = "test_var",
    type = "int",
    docstring = "Some doc",
    definition = NIL -- Simulate JSON null
}

print("Testing with definition = NIL")
local status, err = pcall(UI.show_inspection, data_nil_def)
if not status then
    print("Caught expected error: " .. err)
else
    print("Did not crash with definition = NIL")
end

-- Case 2: docstring is vim.NIL
local data_nil_doc = {
    name = "test_var",
    type = "int",
    docstring = NIL, -- Simulate JSON null
    definition = "x = 1"
}

print("Testing with docstring = NIL")
status, err = pcall(UI.show_inspection, data_nil_doc)
if not status then
    print("Caught expected error: " .. err)
else
    print("Did not crash with docstring = NIL")
end

vim.cmd("qall!")
