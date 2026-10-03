-- Copyright (C) 2026 zzz 802.1X Client LuCI Controller
-- Licensed under Apache 2.0

module("luci.controller.zzz", package.seeall)

function index()
	-- Only register the configuration page
	local page = entry({"admin", "services", "zzz"}, cbi("zzz/config"), _("802.1X 客户端"), 60)
	page.dependent = true
	page.acl_depends = { "luci-app-zzz" }
end

-- Get current service status as JSON
-- (Removed status functions to simplify UI)
