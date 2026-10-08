-- Copyright (C) 2026 zzz 802.1X Client - LuCI Configuration Module
-- Licensed under Apache 2.0

local fs = require "nixio.fs"
local nixio = require "nixio"

-- Escape INI syntax without changing the bytes consumed by config.c.
local function ini_value(value)
	return (tostring(value or ""):gsub(".", function(char)
		if char == "\\" or char == ";" or char:match("%s") then
			return string.format("\\x%02X", string.byte(char))
		end
		return char
	end))
end

local function validate_credential(self, value)
	if not value or value == "" or value:find("[%z\r\n]") then
		return nil, "不能为空或包含换行/NUL 字符。"
	end
	if #ini_value(value) > 180 then
		return nil, "内容过长，超过认证客户端 INI 配置行长度限制。"
	end
	return value
end

local function validate_positive(self, value)
	local number = tonumber(value)
	if not number or number < 1 or number > 86400 or number % 1 ~= 0 then
		return nil, "请输入 1 到 86400 之间的整数秒数。"
	end
	return value
end

local function save_config(content)
	local path, file
	for attempt = 1, 10 do
		path = "/etc/config.ini.tmp." .. nixio.getpid() .. "." .. attempt
		-- nixio parses modes as octal digit strings; a decimal 384 is rejected.
		file = nixio.open(path, nixio.open_flags("wronly", "creat", "excl"), "600")
		if file then break end
	end
	if not file then return nil end
	local written = file:writeall(content)
	local synced = written == #content and file:sync()
	local closed = file:close()
	if not synced or not closed or not fs.rename(path, "/etc/config.ini") then
		fs.unlink(path)
		return nil
	end
	return true
end

local m, s, o
local stop_requested = false

m = Map("zzz", "802.1X 客户端配置",
	"配置 zzz 802.1X EAPOL 认证客户端，用于校园网或企业网接入。")

-- -----------------------------------------------------------
--  Section: main
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "基础设置")
s.addremove = false

o = s:option(ListValue, "device", "网络接口",
	"选择连接认证网络的实际网口；标记为 WAN 的接口来自 OpenWrt 网络配置。")
o.rmempty = false

-- Enumerate actual Ethernet devices rather than logical UCI interface names.
o.validate = function(self, value)
	if not value or #value >= 16 or value:find("[^%w_.:-]") then
		return nil, "请选择有效的网络接口。"
	end
	local device_type = fs.readfile("/sys/class/net/" .. value .. "/type") or ""
	if not device_type:match("^%s*1%s*$") then
		return nil, "所选接口暂不可用，请检查网络配置或重新选择。"
	end
	return value
end

-- This also includes VLAN and bridge devices usable by the libpcap backend.
local wan_devices = {}
local wan_names = m.uci:get("network", "wan", "device")
	or m.uci:get("network", "wan", "ifname") or ""
for name in wan_names:gmatch("%S+") do
	wan_devices[name] = true
end

local devices, seen = {}, {}
local entries = fs.dir("/sys/class/net")
if entries then
	for name in entries do
		local device_type = fs.readfile("/sys/class/net/" .. name .. "/type") or ""
		if name ~= "lo" and device_type:match("^%s*1%s*$") then
			devices[#devices + 1] = name
			seen[name] = true
		end
	end
end

table.sort(devices, function(a, b)
	if wan_devices[a] ~= wan_devices[b] then
		return wan_devices[a] == true
	end
	return a < b
end)

for _, name in ipairs(devices) do
	local label = name
	if wan_devices[name] then
		label = label .. " (WAN)"
	end
	o:value(name, label)
end

-- Keep an existing configuration visible even while its device is absent.
local configured_device = m.uci:get("zzz", "main", "device")
if configured_device and configured_device ~= "" and not seen[configured_device] then
	o:value(configured_device, configured_device .. " (当前配置，接口暂不可用)")
end

if #devices == 0 then
	o.description = o.description .. " 当前未发现可用网口，请检查网络配置。"
end

o = s:option(Value, "username", "用户名",
	"您的 802.1X 校园网/企业网账号。")
o.rmempty = false
o.validate = validate_credential

o = s:option(Value, "password", "密码",
	"您的 802.1X 校园网/企业网密码。")
o.password = true
o.rmempty = false
o.validate = validate_credential

-- Advanced EAP settings
o = s:option(ListValue, "eap_method", "EAP 认证方法",
	"当前后端仅实现 EAP-MD5，其余方法保留供未来扩展，选择后不影响实际认证行为。")
o:value("", "默认 (EAP-MD5)")
o:value("MD5", "EAP-MD5")
o:value("PEAP", "EAP-PEAP (暂不支持)")
o:value("TTLS", "EAP-TTLS (暂不支持)")
o:value("TLS", "EAP-TLS (暂不支持)")
o.rmempty = true

o = s:option(ListValue, "phase2", "第二阶段认证 (Phase 2)",
	"EAP-MD5 不使用第二阶段，此选项仅在未来支持 PEAP/TTLS 后生效。")
o:value("", "无 / 自动")
o:value("MSCHAPv2", "MSCHAPv2")
o:value("MSCHAP", "MSCHAP")
o:value("PAP", "PAP")
o:value("CHAP", "CHAP")
o:value("GTC", "GTC")
o.rmempty = true

-- -----------------------------------------------------------
--  Section: Auto-Reconnect
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "自动重连")
s.addremove = false

o = s:option(Flag, "auto_reconnect", "启用自动重连",
	"当网络断开或认证掉线时自动重新连接。")
o.rmempty = false

o = s:option(Value, "check_interval", "检测间隔 (秒)",
	"多久检查一次网络连通性。")
o.datatype = "uinteger"
o.default = "30"
o.validate = validate_positive

o = s:option(Value, "max_retries", "最大重试次数",
	"网络检测失败后的主动重连次数：-1 表示无限，0 表示不主动重连。进程退出由 procd 单独拉起。")
o.datatype = "integer"
o.default = "-1"
o.validate = function(self, value)
	local number = tonumber(value)
	if not number or number < -1 or number > 100000 or number % 1 ~= 0 then
		return nil, "请输入 -1（无限）、0（不重试）或最多 100000 次。"
	end
	return value
end

o = s:option(Value, "retry_delay", "重试延迟 (秒)",
	"每次重试之间的等待时间。")
o.datatype = "uinteger"
o.default = "10"
o.validate = validate_positive

o = s:option(Value, "gateway_ip", "网关 IP",
	"自定义 IPv4 检测目标（填写后以该目标为准）。留空时检测公网 IP，网关可达不等于外网可用。")
o.datatype = "ip4addr"
o.rmempty = true

-- -----------------------------------------------------------
--  Section: Anti-Detection
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "防检测 (校园网突破)")
s.addremove = false

o = s:option(Flag, "fix_ttl", "固定 TTL (防共享检测)",
	"将 IPv4 数据包 TTL 设为 64。支持 nftables；iptables 需要 iptables-mod-ipopt。不能保证规避所有共享检测。")
o.rmempty = false

o = s:option(Flag, "disable_ipv6", "禁用 IPv6",
	"服务运行时禁用 IPv6，停止或取消勾选后恢复此前的 IPv6 设置。")
o.rmempty = false

-- -----------------------------------------------------------
--  Custom save handler: sync to /etc/config.ini
-- -----------------------------------------------------------
m.on_after_commit = function(self)
	local uci = require("luci.model.uci").cursor()
	local vals = uci:get_all("zzz", "main") or {}
	
	-- Serialize in memory, then replace the file atomically with mode 0600.
	local lines = {}
	local f = { write = function(_, line) lines[#lines + 1] = line end }
	do
		f:write("[auth]\n")
		f:write("device=" .. tostring(vals.device or "eth0") .. "\n")
		f:write("username=" .. ini_value(vals.username) .. "\n")
		f:write("password=" .. ini_value(vals.password) .. "\n")

		if vals.eap_method and vals.eap_method ~= "" then
			f:write("\n[eap]\n")
			f:write("method=" .. tostring(vals.eap_method) .. "\n")
			if vals.phase2 and vals.phase2 ~= "" then
				f:write("phase2=" .. tostring(vals.phase2) .. "\n")
			end
		end

		if vals.auto_reconnect == "1" then
			f:write("\n[watchdog]\n")
			f:write("enabled=1\n")
			f:write("interval=" .. tostring(vals.check_interval or "30") .. "\n")
			f:write("max_retries=" .. tostring(vals.max_retries or "-1") .. "\n")
			f:write("retry_delay=" .. tostring(vals.retry_delay or "10") .. "\n")
			if vals.gateway_ip and vals.gateway_ip ~= "" then
				f:write("gateway_ip=" .. tostring(vals.gateway_ip) .. "\n")
			end
		end

		if vals.fix_ttl == "1" or vals.disable_ipv6 == "1" then
			f:write("\n[anti_detection]\n")
			if vals.fix_ttl == "1" then f:write("fix_ttl=1\n") end
			if vals.disable_ipv6 == "1" then f:write("disable_ipv6=1\n") end
		end

		if not fs.chmod("/etc/config/zzz", "600") or
		   not save_config(table.concat(lines)) then
			self.message = "配置文件保存失败；认证服务未重启，请检查存储空间和文件权限。"
			return
		end
		
		-- Restart service to apply new config
		if not stop_requested then
			os.execute("/etc/init.d/zzz restart >/dev/null 2>&1")
		end
	end
end

-- Function to read log output via logread
function m.action_logread()
	local result = {}
	local f = io.popen('logread | grep -i "zzz" | tail -n 50 2>/dev/null')
	if f then
		result.log = f:read("*a") or ""
		f:close()
		if result.log == "" then
			result.log = "(系统日志中暂无 zzz 的相关输出)"
		end
	else
		result.log = "(无法读取系统日志)"
	end
	return result.log
end

-- Add a custom section to display status and logs
s2 = m:section(NamedSection, "main", "zzz", "服务状态与日志")
s2.addremove = false

o2 = s2:option(DummyValue, "_status", "运行状态")
o2.rawhtml = true
o2.cfgvalue = function(self, section)
	local pid_f = io.popen("pidof zzz 2>/dev/null")
	local pid = pid_f:read("*line")
	pid_f:close()

	if pid and pid ~= "" then
		local state = (fs.readfile("/var/run/zzz-connectivity") or ""):match("%S+")
		local labels = {
			checking = "正在检测网络",
			online = "检测目标可达",
			offline = "网络检测失败",
			retry_limit = "已达重连次数上限"
		}
		local label = labels[state] or "未启用网络检测"
		local color = (state == "offline" or state == "retry_limit") and "orange" or "green"
		return '<span style="color:' .. color .. '; font-weight:bold;">进程运行中 (PID: ' ..
			pid .. ')；' .. label .. '</span>'
	else
		return '<span style="color:blue; font-weight:bold;">已停止</span>'
	end
end

-- 手动控制按钮
o_run = s2:option(Button, "_run", "启动/重启服务")
o_run.inputtitle = "▶ 运行 / 重启"
o_run.inputstyle = "apply"
o_run.write = function(self, section)
	os.execute("logger -t zzz-init 'WebUI: Start/Restart button clicked'")
	os.execute("/etc/init.d/zzz restart >/dev/null 2>&1")
end

o_stop = s2:option(Button, "_stop", "停止服务")
o_stop.inputtitle = "■ 停止"
o_stop.inputstyle = "reset"
o_stop.write = function(self, section)
	stop_requested = true
	os.execute("logger -t zzz-init 'WebUI: Stop button clicked'")
	os.execute("/etc/init.d/zzz stop >/dev/null 2>&1")
end

o3 = s2:option(DummyValue, "_logs", "最近日志")
o3.rawhtml = true
o3.cfgvalue = function(self, section)
	local logs = m.action_logread()
	-- Escape html entities in logs
	logs = logs:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return '<pre style="background:#1e1e1e; color:#d4d4d4; padding:10px; border-radius:4px; max-height:200px; overflow-y:auto; font-size:12px; font-family:monospace; margin-bottom:0; white-space:pre-wrap;">' .. logs .. '</pre>'
end

return m
