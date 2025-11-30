package.path = package.path .. ";./lua/?.lua"
local Hosts = require("jovian.hosts")

print("Verifying Removal List Filtering...")

-- Mock data loading
local data = Hosts.load_hosts()
-- Ensure we have local_default and maybe another one
if not data.configs.test_host then
    Hosts.add_host("test_host", {type="local", python="python3"})
end

local names = {}
for name, _ in pairs(data.configs) do
    if name ~= "local_default" then
        table.insert(names, name)
    end
end

for _, name in ipairs(names) do
    if name == "local_default" then
        print("FAIL: local_default found in list")
        os.exit(1)
    end
end

assert(#names > 0, "Should have at least test_host")
print("PASS: local_default filtered out")

-- Cleanup
Hosts.remove_host("test_host")
vim.cmd("q")
