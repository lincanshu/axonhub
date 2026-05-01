# 前端构建
FROM node:20-alpine AS frontend-builder
WORKDIR /build
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY ./frontend .
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm build

FROM alpine AS frontend-dist
COPY --from=frontend-builder /build/dist /dist

# 后端构建
FROM golang:alpine AS backend-builder
WORKDIR /build

RUN apk add --no-cache git ca-certificates tzdata

COPY go.mod go.sum ./
COPY llm/go.mod llm/go.sum llm/
RUN GOTOOLCHAIN=auto go mod download

COPY . .
COPY --from=frontend-dist /dist /build/internal/server/static/dist

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux

RUN GOTOOLCHAIN=auto go build \
    -tags=nomsgpack \
    -ldflags "-s -w -X 'github.com/looplj/axonhub/internal/build.Version=dev' -X 'github.com/looplj/axonhub/internal/build.BuildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)'" \
    -o axonhub \
    ./cmd/axonhub

# 最终运行
FROM alpine
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=backend-builder /build/axonhub /app/axonhub

EXPOSE 8090
ENTRYPOINT ["/app/axonhub"]