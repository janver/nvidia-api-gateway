# syntax=docker/dockerfile:1

FROM node:20-bookworm AS frontend-builder
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM golang:1.23-bookworm AS backend-builder
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -o /out/nvidia-api-gateway ./main.go

# xray-fetcher: 仅支持 Linux 容器（Docker 标准行为）
# Windows 宿主机运行 Docker 时使用 Linux 容器，xray 下载 Linux 版本是正确的。
# 若需要在 Windows 宿主机上直接运行（非 Docker），xray 会在启动时自动下载对应平台版本。
FROM debian:bookworm-slim AS xray-fetcher
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG XRAY_VERSION=v26.3.27
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip && apt-get clean
RUN set -e; \
    if [ "${TARGETOS:-linux}" != "linux" ]; then \
        echo "Docker image supports Linux containers only; set --platform linux/<arch> on Windows hosts" >&2; \
        exit 1; \
    fi; \
    case "${TARGETARCH:-amd64}" in \
        amd64)  asset="Xray-linux-64.zip" ;; \
        arm64)  asset="Xray-linux-arm64-v8a.zip" ;; \
        arm)    asset="Xray-linux-arm32-v7a.zip" ;; \
        386)    asset="Xray-linux-32.zip" ;; \
        *)      echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /out/xray; \
    # 优先从 GitHub 下载，失败时允许构建继续（运行时会自动重试下载）
    curl -fsSL --retry 3 --retry-delay 5 \
        -o /out/xray/api_asset_download.zip \
        "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${asset}" \
    && unzip -j /out/xray/api_asset_download.zip xray geoip.dat geosite.dat -d /out/xray \
    && chmod +x /out/xray/xray \
    || (echo "Warning: xray download failed, will retry at runtime" >&2; mkdir -p /out/xray)

FROM node:20-bookworm-slim
ARG XRAY_VERSION=v26.3.27
WORKDIR /app
ENV NODE_ENV=production \
    PORT=18080 \
    BACKEND_PORT=18080 \
    FRONTEND_PORT=14000 \
    API_BASE_URL=http://127.0.0.1:18080 \
    GATEWAY_DATA_DIR=/app/var/data \
    XRAY_CORE_DIR=/app/bin/xray \
    XRAY_VERSION=${XRAY_VERSION}
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl dumb-init && apt-get clean
COPY frontend/package.json frontend/package-lock.json /app/frontend/
RUN cd /app/frontend && npm ci --omit=dev
COPY --from=frontend-builder /app/frontend/.next /app/frontend/.next
COPY --from=frontend-builder /app/frontend/public /app/frontend/public
COPY --from=frontend-builder /app/frontend/next.config.ts /app/frontend/next.config.ts
COPY --from=backend-builder /out/nvidia-api-gateway /app/nvidia-api-gateway
COPY --from=xray-fetcher /out/xray/ /app/bin/xray/
COPY docker/entrypoint.sh /app/docker/entrypoint.sh
RUN sed -i 's/\r$//' /app/docker/entrypoint.sh
RUN mkdir -p /app/var/data /app/bin/xray \
    && chmod +x /app/nvidia-api-gateway /app/docker/entrypoint.sh \
    && ([ -f /app/bin/xray/xray ] && chmod +x /app/bin/xray/xray || true)
EXPOSE 18080 14000
VOLUME ["/app/var/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${BACKEND_PORT}/health >/dev/null || exit 1
ENTRYPOINT ["dumb-init", "--"]
CMD ["/app/docker/entrypoint.sh"]
