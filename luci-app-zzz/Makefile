include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zzz
PKG_RELEASE:=2
PKG_VERSION:=1.0.0
PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=Apache-2.0
LUCI_TITLE:=LuCI Support for zzz (802.1X Client)
LUCI_DEPENDS:=+luci-base +libpcap

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-zzz
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI Support for zzz (802.1X Client)
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +zzz-client
endef

define Package/luci-app-zzz/description
  LuCI frontend for zzz sleepy 802.1X client.
  Provides a web UI to configure and manage 802.1X authentication,
  including auto-reconnect on network disconnection.
endef

define Build/Compile
endef

define Package/luci-app-zzz/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_BIN) files/luci/controllers/zzz.lua $(1)/usr/lib/lua/luci/controller/zzz.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/zzz
	$(INSTALL_BIN) files/luci/model/cbi/zzz/config.lua $(1)/usr/lib/lua/luci/model/cbi/zzz/config.lua

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/etc/init.d/zzz $(1)/etc/init.d/zzz

	$(INSTALL_DIR) $(1)/etc/zzz
	$(INSTALL_BIN) files/etc/zzz/check_network.sh $(1)/etc/zzz/check_network.sh
	$(INSTALL_BIN) files/etc/zzz/watchdog.sh $(1)/etc/zzz/watchdog.sh
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/etc/config/zzz $(1)/etc/config/zzz

	$(INSTALL_DIR) $(1)/www/l-static-resources
endef

$(eval $(call BuildPackage,luci-app-zzz))
