# GHCR 多架构 Docker 镜像打包实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为当前项目添加 GitHub Actions workflow，在 main 分支、v* 标签和手动触发时构建并发布 linux/amd64 与 linux/arm64 Docker 镜像到 GitHub Container Registry。

**架构：** 使用 GitHub Actions 的 Docker 官方 actions 组成 CI 流水线：checkout 源码，启用 QEMU 和 Buildx，使用 GITHUB_TOKEN 登录 GHCR，metadata-action 生成标签和 labels，build-push-action 构建并推送多架构镜像。项目现有 Dockerfile 已支持 TARGETOS/TARGETARCH 与 XRAY_VERSION，因此 workflow 只负责传入构建参数和发布策略。

**技术栈：** GitHub Actions、Docker Buildx、GHCR、docker/setup-qemu-action、docker/setup-buildx-action、docker/login-action、docker/metadata-action、docker/build-push-action。

---

## 文件结构

- 创建：`.github/workflows/docker-build.yml`
  - 职责：定义 GHCR 多架构 Docker 镜像构建、打标签、推送流程。
- 参考：`Dockerfile`
  - 职责：现有多阶段镜像构建，已支持 `ARG TARGETOS`、`ARG TARGETARCH`、`ARG XRAY_VERSION`。
- 参考：`docker-compose.yml`
  - 职责：本地容器部署配置，镜像运行时端口、数据卷和环境变量保持不变。

## 任务 1：创建 GHCR 多架构构建 workflow

**文件：**
- 创建：`.github/workflows/docker-build.yml`
- 参考：`Dockerfile:10-17`
- 参考：`Dockerfile:22-46`

- [ ] **步骤 1：创建 workflow 文件**

写入 `.github/workflows/docker-build.yml`：

```yaml
name: Build Multi-Arch Docker Image

on:
  push:
    branches:
      - main
    tags:
      - "v*"
  workflow_dispatch:
    inputs:
      xray_version:
        description: "Xray Core version used during image build"
        required: false
        default: "v26.3.27"

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/nvidia-api-gateway
          tags: |
            type=ref,event=branch
            type=ref,event=tag
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            BUILDKIT_INLINE_CACHE=1
            TARGETOS=linux
            XRAY_VERSION=${{ github.event.inputs.xray_version || 'v26.3.27' }}
          provenance: false
```

- [ ] **步骤 2：确认 workflow 关键行为**

检查 `.github/workflows/docker-build.yml` 满足：

```text
- push main 时触发
- push v* tag 时触发
- workflow_dispatch 可手动触发
- permissions.packages 为 write
- 登录 registry 为 ghcr.io
- 镜像名为 ghcr.io/${{ github.repository_owner }}/nvidia-api-gateway
- platforms 为 linux/amd64,linux/arm64
- push 为 true
- cache-from/cache-to 使用 type=gha
- build-args 传入 TARGETOS=linux 和 XRAY_VERSION
```

- [ ] **步骤 3：运行本地静态检查**

运行：

```powershell
Get-Content ".github/workflows/docker-build.yml"
```

预期：文件完整输出，YAML 缩进为两个空格，包含 `permissions:`、`Login to GitHub Container Registry`、`platforms: linux/amd64,linux/arm64`。

- [ ] **步骤 4：查看 git diff**

运行：

```powershell
git diff -- .github/workflows/docker-build.yml
```

预期：只新增 `.github/workflows/docker-build.yml`，没有修改 Dockerfile 或 docker-compose。

- [ ] **步骤 5：Commit**

运行：

```powershell
git add .github/workflows/docker-build.yml docs/superpowers/plans/2026-06-02-ghcr-docker-build.md
git commit -m @'
ci: 添加 GHCR 多架构 Docker 镜像构建

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

预期：commit 成功，提交包含 workflow 和实现计划。

## 自检结果

- 规格覆盖度：已覆盖 GHCR 发布、main/tag/manual 触发、多架构、标签、缓存、构建参数与权限。
- 占位符扫描：未包含 TODO、待定、后续实现等占位符。
- 类型/字段一致性：workflow 中使用的 `XRAY_VERSION` 与 Dockerfile `ARG XRAY_VERSION` 一致；`TARGETOS=linux` 与 Dockerfile `ARG TARGETOS` 一致；`TARGETARCH` 由 Buildx 按 platform 自动注入，不在 workflow 中手动覆盖。
