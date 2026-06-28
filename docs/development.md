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
- 使用 `~/.config/clash.meta` 作为工作目录。
- 使用 `~/.config/clash.meta/config.yaml` 作为默认配置文件。
- 以子进程方式启动 mihomo。
- 通过 `127.0.0.1:9090` 的 `external-controller` 读取和修改运行状态。

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

TUN 模式、系统代理修改等能力在 macOS 上可能需要授权。当前应用已经完成 UI、配置面、进程生命周期和 controller API 集成；生产版本建议增加类似 ClashX.Meta `ProxyConfigHelper` 的 privileged helper，用于处理需要更高权限的系统操作。
