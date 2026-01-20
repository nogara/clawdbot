FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# Architecture detection for multi-platform builds
ARG TARGETARCH

ARG CLAWDBOT_DOCKER_APT_PACKAGES="socat"
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
  fi

# Install Go 1.23 for building wacli (requires Go 1.22+)
ARG GO_VERSION=1.23.5
RUN set -ex; \
  ARCH="${TARGETARCH:-amd64}"; \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local && \
  ln -s /usr/local/go/bin/go /usr/local/bin/go && \
  ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Install skill binaries
RUN set -ex; \
  ARCH="${TARGETARCH:-amd64}"; \
  # Install gogcli (Gmail CLI)
  GOGCLI_VERSION=$(curl -s https://api.github.com/repos/steipete/gogcli/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//'); \
  curl -L "https://github.com/steipete/gogcli/releases/download/v${GOGCLI_VERSION}/gogcli_${GOGCLI_VERSION}_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin gogcli && \
  mv /usr/local/bin/gogcli /usr/local/bin/gog && \
  chmod +x /usr/local/bin/gog; \
  # Install goplaces (Google Places CLI)
  GOPLACES_VERSION=$(curl -s https://api.github.com/repos/steipete/goplaces/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//'); \
  curl -L "https://github.com/steipete/goplaces/releases/download/v${GOPLACES_VERSION}/goplaces_${GOPLACES_VERSION}_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin goplaces && \
  chmod +x /usr/local/bin/goplaces; \
  # Install wacli (WhatsApp CLI) via go install
  GOBIN=/usr/local/bin go install github.com/steipete/wacli/cmd/wacli@latest

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

ENV NODE_ENV=production

CMD ["node", "dist/index.js"]
