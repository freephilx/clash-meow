# 开发文档

## 项目结构

ClashMeow 以 Xcode 工程作为主要开发入口，Swift Package Manager 作为命令行构建方式保留。

核心目录：

- `ClashMeow.xcodeproj`：macOS GUI 工程。
- `Sources/ClashMeow`：SwiftUI 应用源码。
- `Sources/ClashMeow/Resources`：示例配置、资源和 asset catalog。
- `scripts/install_mihomo.sh`：下载 mihomo 内核。
- `scripts/package_app.sh`：本地打包脚本。

## mihomo 集成方式

当前实现方式：

- 将 mihomo 作为应用资源或本地可执行文件发现。
- 使用 `~/.config/clash-meow` 作为工作目录。
- 使用 `~/.config/clash-meow/config.yaml` 作为默认配置文件。
- App bundle 运行时通过 `com.clash.meow.helper` 以 root 启动 mihomo；SwiftPM 或非 app bundle 调试环境保留普通子进程启动路径。
- 通过 `127.0.0.1:9090` 的 `external-controller` 读取和修改运行状态。

持久化路径和规则见 [持久化](持久化.md)。

应用按以下顺序查找 mihomo：

1. 已构建 app 内的 `Contents/Resources/mihomo`
2. SwiftPM 运行时的 `Sources/ClashMeow/Resources/mihomo`
3. `/opt/homebrew/bin/mihomo`
4. `/usr/local/bin/mihomo`
5. `/usr/bin/mihomo`

## 安装或更新 mihomo

```bash
./scripts/install_mihomo.sh
```

脚本会下载当前平台可用的 mihomo，并写入：

```text
Sources/ClashMeow/Resources/mihomo
```

该文件是下载产物，已被 `.gitignore` 忽略。

## Xcode 开发

打开工程：

```bash
open ClashMeow.xcodeproj
```

选择 `ClashMeow` scheme，目标选择 `My Mac`，然后运行。

## 命令行构建

构建 Xcode 工程：

```bash
xcodebuild -project ClashMeow.xcodeproj -scheme ClashMeow -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

SwiftPM 构建：

```bash
swift build
```

## 配置校验

安装 mihomo 后，可以检查示例配置是否有效：

```bash
Sources/ClashMeow/Resources/mihomo -t -f Sources/ClashMeow/Resources/sampleConfig.yaml
```

## 本地打包

```bash
./scripts/package_app.sh
```

产物路径：

```text
dist/Clash Meow.app
```

## 生产化说明

TUN 模式、系统代理修改、端口释放等能力在 macOS 上可能需要授权。当前应用已经集成 `com.clash.meow.helper` privileged helper：启动时必须校验并安装 helper；App bundle 下 mihomo 的启动、停止和重启统一由 helper 以 root 托管；普通权限无法释放端口时也由 helper 处理端口释放。

本地 `Sign to Run Locally` 构建使用 identifier-only 的 helper 授权要求，便于开发机反复编译和安装。正式签名发布时，应使用稳定 Developer ID，并把 app/helper 的授权 requirement 收紧到对应的 designated requirement。
