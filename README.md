# luci-app-zzz

OpenWrt 的 LuCI 图形界面插件，用于配置和管理 [zzz](https://github.com/diredocks/zzz) —— 一个基于 802.1X EAPOL 协议的校园网/企业网认证客户端。

> 本项目基于 [diredocks/zzz](https://github.com/diredocks/zzz) 开发,故文件夹命名沿用zzz.软件提供 LuCI 管理界面并添加了统一ttl用于简单的防检测，并对 zzz-client 进行了针对性修改。感谢原作者的工作。

**已测试环境：（H3C iNode 802.1X 认证）**

---

## 功能

- 在 LuCI 界面中配置 802.1X 认证参数（网络接口、用户名、密码、EAP 方法等）
- 支持开机自动认证
- 支持手动启动/停止认证服务
- 自动列出实际认证网口，优先标记 WAN；校验账号、密码和重连参数
- 原子保存认证配置，账号密码配置文件权限为 `0600`
- 自动重连仅重启认证进程，保留监控计数；停止按钮不会被保存回调重新启动
- 支持 nftables/iptables 的独立 TTL 规则；禁用 IPv6 后可恢复原设置

---

## 安装


### 使用方法：fork 项目自行编译

见下方[自行编译](#自行编译)章节。

---

## 配置

安装完成后，在 LuCI 界面中进入 **服务 → 802.1X 客户端**，填写以下信息：

![alt text](zzzlicent.png)

网络接口现在使用下拉选择，自动列出路由器当前存在的以太网、VLAN 和桥接口。
OpenWrt 的 `wan` 配置对应的网口会标记为 `WAN` 并优先显示；请选择实际连接认证网络的接口。
已有配置的接口如果暂时不存在，仍会保留并标记为“当前配置，接口暂不可用”。
填写完成后点击**保存并应用**，服务会自动启动并开始认证。

自动重连默认检查公网 IP，自动发现的网关可达不会直接视为外网正常。
如果所在网络阻止公网 ICMP，请填写一个允许 Ping 的自定义 IPv4 检测目标。
“最大重试次数”限制监控主动发起的重连，`-1` 为无限，`0` 为不主动重连；
认证进程退出后的自动拉起仍由 procd 独立管理。
界面分别显示进程状态和检测目标连通状态，检测目标可达不代表已验证认证成功。

账号密码中的空白、分号和反斜杠以可逆 INI 转义保存，这不是加密。
升级旧版本前请先停止旧服务，让旧脚本清理未标记归属的 TTL 规则。
新版本只清理自身的 `zzz_ttl` nftables 表或 `ZZZ_TTL` iptables 链。

### 回归检查

在 Linux/WSL 环境中运行（需要 GCC，以及 Lua 5.1 和 5.4 共享库）：

```sh
python3 tests/run_regression.py
```

检查 Lua 5.1/5.4 下的页面模型和控制器注册、ACL 打包、配置特殊字符往返、
保存失败保护、重连次数上限、连通性判断及 IPv6 状态恢复。
系统和网络操作均通过模拟验证；仍需在目标 OpenWrt 路由器上确认实际运行。

---

## 编译方法



### 1. Fork 本仓库

点击页面右上角的 **Fork** 按钮，将仓库复制到你自己的 GitHub 账号下。

### 2. 确认 SDK 版本

默认工作流编译红米 AC2100（RM2100）的软件安装包，使用 OpenWrt 25.12.5、
`ramips/mt7621` 目标和 `mipsel_24kc` 包架构。产物为 `.apk`，不是 Android 应用或路由器刷机固件。
OpenWrt 25.12 使用 apk 包管理器，不要安装之前为 23.05 构建的 `.ipk`。
客户端直接编译本仓库的 `zzz-client-source/src` 和 `include`，不会下载上游 HEAD 替代本地代码。
如果路由器的 OpenWrt 版本不同，请使用匹配版本的 SDK 重新编译。

编辑 `.github/workflows/build.yml`，修改 SDK 下载链接以匹配你的路由器 OpenWrt 版本和架构：

```yaml
- name: Setup OpenWrt SDK
  run: |
    wget https://downloads.openwrt.org/releases/[版本]/targets/[架构]/[子架构]/openwrt-sdk-[...].tar.zst
```

SDK 下载地址可在 [OpenWrt 官方下载页面](https://downloads.openwrt.org/releases/) 查找，找到对应版本和架构的目录，下载文件名包含 `openwrt-sdk` 的压缩包。

### 3. 触发编译

有两种触发方式：

**自动触发**：向 `main` 分支 push 代码时自动编译。

**手动触发**：
1. 进入你 fork 的仓库，点击顶部 **Actions** 标签页
2. 左侧选择 **Build OpenWrt Package**
3. 点击 **Run workflow** → **Run workflow**

### 4. 下载编译产物

编译完成后，在对应的 workflow 运行记录页面底部的 **Artifacts** 中下载
`zzz-rm2100-openwrt-25.12.5-mipsel_24kc`，其中包含 `.apk`、构建信息和 SHA256 校验文件。
安装客户端和 LuCI 插件时需要 `libpcap` 和 `luci-compat` 等依赖。

### LuCI 25.12 兼容说明

现有页面保留 Lua CBI 实现，不要求改写成 JavaScript。
`luci-compat` 在 25.12 中依赖 `luci-lua-runtime`，后者提供 Lua 5.1、
`nixio`、Lua UCI 和 ucode/Lua 桥接组件；安装时必须让依赖正常解析。
插件包含 rpcd ACL：读取 `network` 与 `zzz`，仅允许写入 `zzz`。

交叉编译和模拟回归通过不等于真机认证已验证。升级后请用管理员账号确认：
页面能打开、WAN 网口下拉正常、保存并应用能写入 `/etc/config.ini`，
启动/停止按钮有效，日志可显示，以及拔线/恢复后的重连行为。
如果菜单缓存未更新，可重启 rpcd/uhttpd 并重新登录 LuCI。

---

## 关于 zzz

[zzz](https://github.com/diredocks/zzz) 是一个轻量的 802.1X EAPOL 认证客户端，通过 `libpcap` 直接在链路层收发 EAPOL 帧，绕过内核协议栈实现认证，适合在 OpenWrt 等嵌入式 Linux 环境中运行。

本项目使用了 zzz 的核心认证逻辑，并在此基础上进行了修改以适配特定校园网环境。

---

## 免责声明

本项目仅供学习和个人使用，请遵守所在学校或机构的网络使用规定。
