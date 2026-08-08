# Mihomo 制品管理

Clash Meow 采用与 DouWork 相同的锁文件、内容寻址缓存和 Xcode 离线暂存方式，
确保开发构建与发布包使用完全相同、可复核的 Mihomo 制品。

## 锁文件

`RuntimeLocks/mihomo.lock.json` 固定以下信息：

- Mihomo tag、arm64 与 x86_64 下载地址、归档 SHA-256、解压后二进制
  SHA-256 和完整版本输出。
- 对应 tag 的源码归档及 SHA-256。
- GeoData 版本、文件地址及 SHA-256。
- 第三方许可证地址及 SHA-256。
- 允许下载的 HTTPS 域名和应用最低 macOS 版本。

Intel 包使用 Mihomo 的 `amd64-compatible` 制品，以覆盖较早的 Intel CPU。
更新版本时必须同时更新全部 URL、哈希与版本输出，不能只修改 tag。

## 准备与缓存

准备两个架构：

```bash
make setup
```

制品默认存放在：

```text
~/Library/Caches/com.clash.meow/vendor/mihomo
```

可用 `CLASH_MEOW_RUNTIME_CACHE_DIR` 临时覆盖缓存根目录。下载制品以 SHA-256
为文件名保存，解析结果以锁文件 SHA-256 分目录保存，并使用文件锁和原子替换，
允许并发构建安全复用。

常用诊断命令：

```bash
/usr/bin/python3 scripts/mihomo-runtime.py validate-lock
/usr/bin/python3 scripts/mihomo-runtime.py verify --arch all
/usr/bin/python3 scripts/mihomo-runtime.py cache-path
```

## Xcode 暂存

`Stage Mihomo Runtime` build phase 根据 Xcode 的 `ARCHS` 从已校验缓存复制资源，
不执行网络下载。产物布局为：

```text
Contents/Resources/Mihomo/
├── arm64/bin/mihomo 或 x86_64/bin/mihomo
├── GeoData/
├── ThirdPartyLicenses/
└── MANIFEST.json
```

暂存阶段会重新 ad-hoc 签名 Mihomo，并在 manifest 中记录锁文件 SHA、制品 SHA、
版本与 GeoData 信息。发布构建之后，主程序、helper 和 Mihomo 的架构必须一致。

## 运行时约束

应用仅解析当前进程架构对应的包内路径，不接受 Homebrew 或系统 Mihomo。
privileged helper 同样只允许 App bundle 内上述两个规范路径。启动和 helper 重启
前都执行 `mihomo -t` 校验实际运行配置，失败时不释放端口也不启动内核。

## 发布

`make release` 会先通过 `make setup` 准备锁定制品，再调用
`scripts/build-release.sh` 复核缓存、解析 Swift Package 依赖、运行测试，并生成
Apple Silicon 与 Intel 两个 DMG。当前发布流程按项目要求仅使用 ad-hoc 签名，
不执行 Developer ID 签名或 Apple 公证。

可用 `make release` 串行执行打包和 GitHub Release 上传；tag 不存在时，会在
打包成功后通过 Git 推送，再创建 Release。可通过 `RELEASE_TARGET` 指定目标
分支或 commit，通过 `RELEASE_REMOTE` 指定 Git remote。

`release` 分支发生 push 时，GitHub Actions 会自动调用同一套 `make release`
约定，但会把 Swift 测试、arm64 打包和 x86_64 打包拆成并行 Job；全部成功后
再汇总两个 DMG，并以 `v<版本>-build.<run_number>` 创建 prerelease。
