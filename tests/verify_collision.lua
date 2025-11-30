package.path = package.path .. ";./lua/?.lua"
local Hosts = require("jovian.hosts")

print("Verifying Host Collision Check...")

-- Ensure we have a clean state or known state
-- We know 'local_default' exists.
assert(Hosts.exists("local_default") == true, "local_default should exist")
assert(Hosts.exists("non_existent_host") == false, "non_existent_host should not exist")

print("PASS: Exists Check")
vim.cmd("q")
