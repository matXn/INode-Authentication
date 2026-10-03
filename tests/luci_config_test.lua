-- Run with tests/run_regression.py; no OpenWrt or network changes required.
local options, values, writes, permissions = {}, {}, {}, {}
local restart_count, fail_write, fail_rename = 0, false, false
local files = { ["/sys/class/net/wan/type"] = "1\n",
                ["/sys/class/net/eth0/type"] = "1\n",
                ["/sys/class/net/lo/type"] = "772\n" }
local fs = {}
function fs.readfile(path) return files[path] end
function fs.dir()
    local names, index = { "lo", "eth0", "wan" }, 0
    return function() index = index + 1; return names[index] end
end
function fs.chmod(path, mode) permissions[path] = mode; return true end
function fs.rename(src, dst)
    if fail_rename then return nil end
    files[dst], files[src] = files[src], nil
    permissions[dst] = permissions[src]
    return true
end
function fs.unlink(path) files[path] = nil; return true end
package.preload["nixio.fs"] = function() return fs end
package.preload["nixio"] = function()
    return {
        getpid = function() return 42 end,
        open_flags = function(...) return {...} end,
        open = function(path, flags, mode)
            if files[path] then return nil end
            assert(flags[3] == "excl" and mode == 384)
            permissions[path], files[path] = mode, ""
            return {
                writeall = function(_, content)
                    if fail_write then return nil end
                    files[path] = content
                    return #content
                end,
                sync = function() return true end,
                close = function() return true end
            }
        end
    }
end
local cursor = {}
function cursor:get(package, section, key)
    if package == "network" and section == "wan" and key == "device" then return "wan" end
    if package == "zzz" and key == "device" then return values.device end
end
function cursor:get_all() return values end
package.preload["luci.model.uci"] = function()
    return { cursor = function() return cursor end }
end
Value, ListValue, Flag, Button, DummyValue, NamedSection = {}, {}, {}, {}, {}, {}
function Map()
    local map = { uci = cursor }
    function map:section()
        return { option = function(_, kind, key, title, description)
            local option = { description = description, choices = {} }
            function option:value(value, label) self.choices[#self.choices + 1] = {value, label} end
            options[key] = option
            return option
        end }
    end
    return map
end
os.execute = function(command)
    if command:find("/etc/init.d/zzz restart", 1, true) then restart_count = restart_count + 1 end
    return 0
end

values = { device = "wan", username = "user", password = "p \\x41; end ",
           auto_reconnect = "1", check_interval = "30", max_retries = "2",
           retry_delay = "10", fix_ttl = "1", disable_ipv6 = "1" }
local map = assert(loadfile(PROJECT_ROOT .. "/luci-app-zzz/files/luci/model/cbi/zzz/config.lua"))()
assert(options.device.choices[1][1] == "wan")
assert(options.device:validate("wan") == "wan")
assert(options.device:validate("../../etc") == nil)
assert(options.device:validate("missing") == nil)
assert(options.password:validate("normal") == "normal")
assert(options.password:validate("a\nb") == nil)
assert(options.password:validate(string.rep("x", 181)) == nil)
assert(options.check_interval:validate("0") == nil)
assert(options.retry_delay:validate("10") == "10")
assert(options.max_retries:validate("-2") == nil)
assert(options.max_retries:validate("-1") == "-1")
map:on_after_commit()
assert(restart_count == 1 and permissions["/etc/config.ini"] == 384)
assert(permissions["/etc/config/zzz"] == 384)
local original = assert(files["/etc/config.ini"])
local encoded = assert(original:match("password=([^\n]*)"))
local decoded = encoded:gsub("\\x(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
assert(decoded == values.password)
assert(original:find("max_retries=2", 1, true))
fail_write = true
map:on_after_commit()
assert(files["/etc/config.ini"] == original and restart_count == 1)
assert(map.message:find("保存失败", 1, true))
fail_write, fail_rename = false, true
map:on_after_commit()
assert(files["/etc/config.ini"] == original and restart_count == 1)
for path in pairs(files) do assert(not path:find("config.ini.tmp", 1, true)) end
fail_rename = false
options._stop:write("main")
map:on_after_commit()
assert(restart_count == 1, "Saving after Stop must not restart the service")
print("PASS: Lua interface selection, validation, credential escaping, atomic save failures")

-- Validate legacy controller registration on both supported test runtimes.
local page = {}
local env = setmetatable({
    module = function() end,
    _ = function(value) return value end,
    cbi = function(path) assert(path == "zzz/config"); return path end,
    entry = function(path, target)
        assert(table.concat(path, "/") == "admin/services/zzz")
        assert(target == "zzz/config")
        return page
    end
}, { __index = _G })
local path = PROJECT_ROOT .. "/luci-app-zzz/files/luci/controllers/zzz.lua"
local controller
if setfenv then
    controller = assert(loadfile(path))
    setfenv(controller, env)
else
    controller = assert(loadfile(path, "t", env))
end
controller()
env.index()
assert(page.dependent and page.acl_depends[1] == "luci-app-zzz")
