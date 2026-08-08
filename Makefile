.PHONY: setup release

# 准备并校验锁定的 arm64 与 x86_64 Mihomo 运行时。
setup:
	./scripts/prepare-mihomo-runtime.sh --arch arm64 --arch x86_64

# 构建双架构发布包，然后创建或更新 GitHub Release。
release: setup
	./scripts/release.sh
