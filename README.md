# Pi Web for macOS

一个用于管理 [Pi Web](https://github.com/agegr/pi-web) 的原生 macOS 菜单栏应用。

无需长期打开终端，即可启动、停止、重启和打开 `@agegr/pi-web`，并通过原生设置界面管理监听地址、端口、Allowed Hosts、工作目录和 Basic Auth。

> [!IMPORTANT]
> 本项目不是 Pi Web 本体，也不是 Pi Web 官方项目。
> Web UI、Pi 会话与模型管理能力由上游 [`@agegr/pi-web`](https://github.com/agegr/pi-web) 提供；本项目负责 macOS 侧的启动、配置和进程管理。

## 为什么做这个项目

Pi Web 本身已经提供完整的浏览器界面，但日常使用时仍需要从终端启动服务、维护启动参数和环境变量。

Pi Web for macOS 将这部分工作收进一个常驻菜单栏的小应用：

- 不需要每次手动输入 `pi-web` 命令
- 可以直接从菜单栏启动、停止和重启服务
- 使用原生设置界面修改常用运行参数
- 自动查找 PATH、Homebrew、Volta、nvm 等常见位置中的 `pi-web` 可执行文件
- 将访问密码保存在 macOS Keychain，而不是普通配置文件中
- 适合把 Pi Web 作为长期运行的本地开发工具使用

## 功能

- **菜单栏控制**：启动、停止、重启、打开 Pi Web
- **服务状态**：显示运行状态、访问地址和启动错误
- **监听配置**：设置监听 IP 与端口
- **环境变量**：`PATH`、`PI_WEB_ALLOWED_HOSTS`、`PI_WEB_PASSWORD`、`PI_WEB_CWD`、`PI_WEB_NO_OPEN`、`NODE_OPTIONS` 均可修改，并支持添加自定义变量
- **Keychain 存储**：`PI_WEB_PASSWORD` 写入 macOS Keychain，不以明文保存在偏好设置中
- **工作目录**：通过图形目录选择器设置 Pi Web 工作目录
- **Node Bin Path**：留空自动扫描 PATH、Homebrew、Volta、nvm，也可手动指定 Node 的 `bin` 目录
- **Pi Web Path**：留空自动检测 `pi-web`，也可直接指定可执行文件路径
- **自动启动**：打开应用后自动启动 Pi Web
- **自动打开网页**：服务启动成功后自动打开浏览器
- **端口冲突处理**：启动前检查并停止占用同一端口的已有 Pi Web 进程
- **本机地址校验**：监听非本机已有 IP 时拒绝启动，避免错误绑定

## 工作方式

```text
Pi Web for macOS
        │
        ├── 读取原生设置 / macOS Keychain
        │
        ├── 查找 pi-web 可执行文件
        │
        └── 启动 @agegr/pi-web
                    │
                    └── Pi / ~/.pi/agent / 本地项目
```

这个应用不会重新实现 Pi Web，也不会内置一套独立的会话或模型系统。

## 系统要求

目前项目面向：

- macOS 11 Big Sur 或更高版本
- Apple Silicon（arm64）或 Intel（x86_64）Mac
- Node.js 22.19.0 或更高版本
- npm
- 全局安装的 `@agegr/pi-web`

Pi Web 的 Node.js 最低版本要求来自上游项目。

## 安装 Pi Web

本项目直接查找 npm 全局安装后生成的 `pi-web` 可执行文件，因此需要先全局安装 Pi Web：

```bash
npm install -g @agegr/pi-web@latest
```

确认安装：

```bash
pi-web --help
```

如果使用 nvm，本应用会直接扫描 `~/.nvm/versions/node/*/bin`。不会 `source ~/.nvm/nvm.sh`，也不会启动登录 Shell。也可以在设置中直接指定 **Node Bin Path** 和 **Pi Web Path**；手动值优先于自动检测。

## 从源码构建

在项目目录执行：

```bash
./build-app.sh
```

脚本会：

1. 使用 Swift Package Manager 编译 Release 版本
2. 创建 `dist/Pi Web.app`
3. 写入 App 的 `Info.plist`
4. 加入 `PiWeb.icns`
5. 使用 ad-hoc 签名
6. 将 App 复制到 `/Applications/Pi Web.app`

也可以只编译 Swift executable：

```bash
swift build -c release
```

## 使用

启动 `Pi Web.app` 后，菜单栏会出现 Pi Web 图标。

菜单中提供：

- 启动 Pi Web
- 停止 Pi Web
- 重启 Pi Web
- 打开 Pi Web
- 设置
- 退出

首次使用建议先打开 **设置**，检查监听 IP、端口、运行时路径、环境变量和工作目录，再启动服务。

## 设置说明

| 设置 | 对应 Pi Web 配置 | 说明 |
| --- | --- | --- |
| 监听 IP | `--hostname` | Pi Web 实际监听的本机网络地址 |
| 端口 | `--port` | Web 服务端口 |
| Node Bin Path | `PATH` | 留空自动检测；填写后把指定 Node `bin` 目录放到最终 PATH 前面 |
| Pi Web Path | 可执行文件 | 留空自动检测 `pi-web`；也可直接指定路径 |
| PATH | `PATH` | 运行时 PATH；留空自动检测生成，支持手动修改或点击重新检测 |
| Allowed Hosts | `PI_WEB_ALLOWED_HOSTS` | 默认环境变量；允许的代理或自定义 Host，多个值使用逗号分隔 |
| 密码 | `PI_WEB_PASSWORD` | 默认环境变量；启用 HTTP Basic Auth，值存放于 macOS Keychain |
| 工作目录 | 进程 cwd | Pi Web 进程实际启动所在目录 |
| PI_WEB_CWD | `PI_WEB_CWD` | 留空跟随工作目录；也可以单独指定不同路径 |
| NODE_OPTIONS | `NODE_OPTIONS` | 传递给 Node.js 的运行参数 |
| 自定义环境变量 | 自定义 | 可在设置中点击“添加变量”追加 |
| 自动启动 | App 设置 | 打开本应用后自动启动 Pi Web |
| 自动打开网页 | App 设置 | 服务启动后由 Launcher 统一在默认浏览器中打开（已默认带 `--no-open` 避免重复拉起） |

修改运行参数后，点击 **应用并重启** 即可让新配置立即生效。

## 局域网访问

如果希望其他设备访问 Pi Web，需要把监听 IP 设置为这台 Mac 实际拥有的局域网地址。

应用启动前会通过系统网络接口检查这个 IP。如果当前 Mac 没有配置该地址，Pi Web 不会启动。

如果通过域名、反向代理或 Tunnel 访问，还需要把对应 Host 加入 **Allowed Hosts**。

## 安全说明

Pi Web 可以访问本地项目、会话，并执行 Agent 工具，因此不要把一个没有保护的实例直接暴露到公网。

如果监听非回环地址，建议至少设置访问密码。

密码由本应用保存在 **macOS Keychain** 中，并在启动 Pi Web 时通过 `PI_WEB_PASSWORD` 环境变量传递。

需要注意：HTTP Basic Auth 本身不会加密网络传输。如果需要跨公网访问，请使用 HTTPS 反向代理、可信 VPN 或安全 Tunnel，不要直接通过明文 HTTP 暴露 Pi Web。

## 与上游 Pi Web 的关系

上游项目：

- [`agegr/pi-web`](https://github.com/agegr/pi-web)
- npm：`@agegr/pi-web`

Pi Web 提供真正的 Web UI，包括 Pi 会话、Agent、模型配置、项目文件、Git 等功能。

本项目只负责 macOS 原生控制层：

```text
上游 Pi Web = Web UI / Agent 功能
本项目       = macOS 菜单栏启动器 / 配置器 / 进程管理器
```

如果遇到 Web UI、Pi 会话、模型 Provider 或 Agent 本身的问题，应优先查看上游 Pi Web 项目；如果问题发生在 macOS 启动、菜单栏、Keychain、Node/npm 发现或进程管理，则属于本项目范围。

## 项目结构

```text
Pi-Web/
├── Package.swift
├── build-app.sh
├── Resources/
│   └── PiWeb.icns
└── Sources/
    └── PiWeb/
        ├── AppDefaults.swift
        ├── PiWebApp.swift
        ├── PiWebController.swift
        └── SecretStore.swift
```

核心实现全部使用 Swift / SwiftUI / AppKit，没有额外 Swift 第三方依赖。

## 开发

```bash
swift build
swift run PiWeb
```

正式打包：

```bash
./build-app.sh
```

## 致谢

感谢 [`agegr/pi-web`](https://github.com/agegr/pi-web) 提供 Pi 的 Web UI。

同时感谢 [Pi Coding Agent](https://github.com/earendil-works/pi) 及其生态项目。
