# 开发文档

## 项目结构

ClashMeow 以 Xcode 工程作为主要开发入口，Swift Package Manager 作为命令行构建方式保留。

核心目录：

- `ClashMeow.xcodeproj`：macOS GUI 工程。
- `Sources/ClashMeow`：SwiftUI 应用源码。
- `Sources/ClashMeow/Resources`：示例配置、资源和 asset catalog。
- `RuntimeLocks/mihomo.lock.json`：Mihomo、GeoData、源码与许可证制品锁。
- `scripts/prepare-mihomo-runtime.sh`：下载并校验锁定制品到用户缓存。
- `scripts/build-release.sh`：构建 Apple Silicon 与 Intel 发布包。

## mihomo 集成方式

当前实现方式与 DouWork 一致：

- 只使用 `RuntimeLocks/mihomo.lock.json` 锁定的 Mihomo 制品。
- 下载阶段同时校验压缩包 SHA-256、解压后二进制 SHA-256、Mach-O 架构、
  最低 macOS 版本及 `mihomo -v` 输出。
- Xcode 构建阶段不联网，仅从校验后的用户缓存按 `ARCHS` 注入内核。
- App 只使用包内 `Contents/Resources/Mihomo/<arch>/bin/mihomo`，不回退到
  Homebrew 或系统目录。
- 使用 `~/.config/clash-meow` 作为工作目录。
- 使用 `~/.config/clash-meow/config.yaml` 作为默认配置文件。
- 每次启动内核前执行 `mihomo -t -d <工作目录> -f <运行配置>`。
- App bundle 运行时通过 `com.clash.meow.helper` 以 root 启动 mihomo；SwiftPM 或非 app bundle 调试环境保留普通子进程启动路径。
- 通过 `127.0.0.1:9090` 的 `external-controller` 读取和修改运行状态。

持久化路径和规则见 [持久化](持久化.md)。

详细的锁文件、缓存和暂存规则见 [Mihomo 制品管理](Mihomo制品管理.md)。

## 准备 Mihomo 依赖

```bash
make setup
```

该命令准备 arm64 和 x86_64 两套锁定依赖。只准备当前架构时，可以直接运行：

```bash
./scripts/prepare-mihomo-runtime.sh
```

`scripts/install_mihomo.sh` 仅作为兼容入口，内部转调上述锁定依赖流程。

## Xcode 开发

打开工程：

```bash
open ClashMeow.xcodeproj
```

选择 `ClashMeow` scheme，目标选择 `My Mac`，然后运行。

首次构建前必须先执行 `make setup` 准备 Mihomo 缓存。Xcode 的
`Stage Mihomo Runtime` 阶段不会访问网络，缺少缓存时会直接失败并提示准备命令。

## 命令行构建

构建 Xcode 工程：

```bash
./scripts/prepare-mihomo-runtime.sh
xcodebuild -project ClashMeow.xcodeproj -scheme ClashMeow -configuration Debug build
```

SwiftPM 构建：

```bash
swift build
```

## 配置校验

准备依赖后，可以把当前架构内核暂存到临时目录并检查示例配置：

```bash
tmpdir="$(mktemp -d)"
./scripts/stage-mihomo-runtime.sh "$tmpdir/Mihomo"
"$tmpdir/Mihomo/$(uname -m)/bin/mihomo" -t -d "$tmpdir" \
  -f Sources/ClashMeow/Resources/sampleConfig.yaml
```

## 本地打包

```bash
./scripts/package_app.sh
```

产物路径：

```text
dist/Clash Meow.app
```

该脚本使用 SwiftPM 快速组装本地 App，不包含 Xcode 工程构建的
privileged helper，不应用于发布。

## 构建发布包

```bash
./scripts/build-release.sh 0.1.0
```

该命令会自动执行以下操作：

1. 下载并严格校验锁文件指定的 arm64 与 x86_64 Mihomo、GeoData、源码和许可证。
2. 解析 Xcode Swift Package 依赖并运行 `swift test`；设置 `SKIP_TESTS=1`
   可以跳过测试。
3. 分别构建 arm64 和 x86_64 Release Archive；每个 App 只包含对应架构的
   主程序、privileged helper 与 Mihomo。
4. 使用 ad-hoc 临时签名生成两个 DMG，并分别生成、复核 SHA-256 文件和挂载验包。

产物路径：

```text
dist/release/Clash-Meow-0.1.0-Apple-Silicon.dmg
dist/release/Clash-Meow-0.1.0-Apple-Silicon.dmg.sha256
dist/release/Clash-Meow-0.1.0-Intel.dmg
dist/release/Clash-Meow-0.1.0-Intel.dmg.sha256
```

可以通过 `BUILD_NUMBER` 设置 `CFBundleVersion`：

```bash
BUILD_NUMBER=12 ./scripts/build-release.sh 0.1.0
```

发布包没有使用 Developer ID 正式签名，也没有提交 Apple 公证，因此在其他
Mac 上可能被 Gatekeeper 阻止。这条命令适合内部测试或手动分发，不属于正式
Apple 发布流程。

## 上传 GitHub Release

上传对应版本的默认产物：

```bash
./scripts/upload-github.sh v0.1.0
```

Release 不存在时，脚本使用 GitHub 自动生成的更新说明创建 Release；Release
和 tag 会默认创建在当前分支。Release 已经存在时，使用 `--clobber` 覆盖同名
附件。也可以显式指定上传文件：

```bash
./scripts/upload-github.sh v0.1.0 path/to/package.dmg path/to/checksum.txt
```

脚本使用已登录的 `gh` CLI，也支持通过 `GH_TOKEN` 鉴权。可选环境变量包括：

- `GITHUB_REPOSITORY=owner/repository`：覆盖目标仓库。
- `RELEASE_TARGET=main`：指定新建 tag 指向的远端分支或 commit。
- `RELEASE_REMOTE=origin`：指定 `make release` 推送新 tag 使用的 Git remote。
- `ALLOW_DIRTY=1`：明确允许从存在未提交修改的工作区构建发布包。
- `RELEASE_NOTES_FILE=CHANGELOG.md`：使用指定 Markdown 作为发布说明。
- `PRERELEASE=1`：创建 prerelease。
- `DRAFT=1`：创建 draft Release。

也可以用一个命令依次完成双架构打包与上传：

```bash
make release
```

该命令默认读取 Xcode 的 `MARKETING_VERSION`，并上传到对应的 `v<版本>` tag；
tag 不存在时，会在打包成功后创建并通过 Git 推送，再创建 GitHub Release。
需要覆盖版本、tag 或目标分支时使用：

```bash
PACKAGE_VERSION=0.1.0 RELEASE_TAG=v0.1.0 RELEASE_TARGET=main make release
```

## 生产化说明

TUN 模式、系统代理修改、端口释放等能力在 macOS 上可能需要授权。当前应用已经集成 `com.clash.meow.helper` privileged helper：启动时必须校验并安装 helper；App bundle 下 mihomo 的启动、停止和重启统一由 helper 以 root 托管；普通权限无法释放端口时也由 helper 处理端口释放。

本地 `Sign to Run Locally` 构建使用 identifier-only 的 helper 授权要求，便于开发机反复编译和安装。正式签名发布时，应使用稳定 Developer ID，并把 app/helper 的授权 requirement 收紧到对应的 designated requirement。
