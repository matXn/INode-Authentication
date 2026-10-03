include $(TOPDIR)/rules.mk

PKG_NAME:=zzz-client
PKG_VERSION:=0.1.1
PKG_RELEASE:=2

PKG_MAINTAINER:=Your Name <your.email@example.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/zzz-client
  SECTION:=net
  CATEGORY:=Network
  TITLE:=sleepy 802.1X client (zzz)
  URL:=https://github.com/diredocks/zzz
  DEPENDS:=+libpcap
endef

define Package/zzz-client/description
  zzz is a lightweight 802.1X (EAPOL) client written in C.
  It handles EAP authentication for campus/corporate networks
  that require 802.1X port-based access control.
endef

# Compile the checked-out source, including the local configuration fixes.
define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) ./src ./include $(PKG_BUILD_DIR)/
endef

# All source files from meson.build (14 files total)
Zzz_SRC_FILES := \
	src/auth.c \
	src/crypto/aes.c \
	src/crypto/aes-md5.c \
	src/crypto/base64.c \
	src/crypto/const.c \
	src/crypto/crypto.c \
	src/crypto/md5.c \
	src/main.c \
	src/packet/packet.c \
	src/packet/send.c \
	src/utils/config.c \
	src/utils/device.c \
	src/utils/ini.c \
	src/utils/log.c \

Zzz_SRC_PATHS := $(addprefix $(PKG_BUILD_DIR)/,$(Zzz_SRC_FILES))
Zzz_OBJ_FILES := $(Zzz_SRC_FILES:.c=.o)
Zzz_OBJ_PATHS := $(addprefix $(PKG_BUILD_DIR)/,$(Zzz_OBJ_FILES))

TARGET_CFLAGS += -D_GNU_SOURCE -std=gnu2x

define Build/Compile
	$(foreach src,$(Zzz_SRC_PATHS),\
		$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_CPPFLAGS) \
			-I$(PKG_BUILD_DIR)/include \
			-I$(PKG_BUILD_DIR)/src \
			-c $(src) -o $(src:.c=.o) || exit 1;
	)
	$(TARGET_CC) $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/zzz \
		$(Zzz_OBJ_PATHS) \
		-lpcap
endef

define Package/zzz-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zzz $(1)/usr/bin/zzz
endef

$(eval $(call BuildPackage,zzz-client))
