# DouClash

<p align="center">
  <strong>简体中文</strong> | <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="Sources/DouClash/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" alt="DouClash 图标" width="128" height="128">
</p>

DouClash 是一款原生 macOS mihomo 图形客户端，用于在一个界面中完成内核运行、配置管理、节点选择、连接观测和网络诊断。

![DouClash 应用截图](docs/images/app-screenshot.png)

## 核心功能

- **内核与配置管理**：启动、停止本地 mihomo 内核，导入本地 YAML 配置或订阅，并支持配置刷新与切换。
- **代理与路由控制**：查看代理组和节点，在直连、规则、全局模式之间切换。
- **macOS 系统集成**：控制系统代理、增强模式（TUN）和局域网访问，支持菜单栏快捷操作。
- **实时状态观测**：展示上传、下载速率与累计流量，查看活动连接和客户端流量排行。
- **网络诊断**：支持代理节点测速和互联网延迟检测，便于快速定位连接问题。
- **原生体验**：使用 SwiftUI 构建，支持 Apple Silicon 和 Intel Mac。

## 系统要求

- macOS 14 Sonoma 或更高版本。
- 系统代理、增强模式和端口处理等功能可能需要管理员授权。

## 从源码运行

仓库目前尚未提供可下载的 GitHub Release。运行前需要准备项目锁定的 mihomo、GeoData 和许可证制品：

```bash
git clone https://github.com/freephilx/clash-meow.git
cd clash-meow
make setup
open DouClash.xcodeproj
```

在 Xcode 中选择 `DouClash` scheme 和 `My Mac` 运行目标，然后启动应用。首次使用时，可以导入订阅或本地 YAML 配置；启动内核后，再按需开启系统代理或增强模式。

命令行构建、测试、打包和发布流程请参阅[开发文档](docs/development.md)。

## 文档

- [概览页](docs/概览.md)
- [配置管理](docs/配置.md)
- [配置切换](docs/切换配置.md)
- [增强模式](docs/增强模式.md)
- [代理测速](docs/代理测速.md)
- [互联网延迟检测](docs/互联网延迟.md)
- [网络诊断报告](docs/网络诊断.md)
- [持久化与数据目录](docs/持久化.md)
- [开发、构建与发布](docs/development.md)

## 参考与致谢

DouClash 的部分产品行为、配置管理、日志处理和 macOS 集成方案参考并对照了以下开源项目：

- [mihomo](https://github.com/MetaCubeX/mihomo)：DouClash 运行和管理的代理内核。
- [ClashX.Meta](https://github.com/MetaCubeX/ClashX.Meta)：参考其 macOS 菜单栏、配置切换、系统代理和 privileged helper 设计。
- [Kumo](https://github.com/ProjectKumo/KumoApp)：参考其 Profile 模型、受控运行时配置、日志和内核生命周期分层设计。
- [Clash Party / Mihomo Party](https://github.com/mihomo-party-org/clash-party)：参考其 Profile 切换、运行时配置生成、热重载和失败回滚策略。

上述项目的版权和许可证归各自项目所有。这里的“参考”指设计调研、行为对照和实现取舍依据；除非另有说明，本仓库不声明复制或再分发这些项目的源代码。

## 许可证

DouClash 以 [GNU General Public License v3.0 only](LICENSE) 授权。
项目分发的第三方组件仍遵循各自的许可证，详情见
[第三方声明](THIRD_PARTY_NOTICES.md)。

## 免责声明

- 本项目代码均有 AI Agent 参与生成或修改。
- 本项目按“现状（AS IS）”提供，不提供任何形式的明示或默示担保。
- 使用本项目产生的网络中断、账号风险、数据丢失、配置错误或系统异常等后果由使用者自行承担。
- 作者不对任何直接、间接、附带、特殊或后果性损失承担责任。
- 为保持项目的生成过程一致，作者建议贡献由 AI Agent 生成或修改的代码，而非完全手写的代码。
