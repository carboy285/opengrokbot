# OpenGrokBot in a container, used from a browser through Web access. EXPERIMENTAL: not yet built or run by the maintainers.
# Build:  docker build -f docker/Dockerfile -t opengrokbot .
# Run:    see docs/DOCKER.md (a password is required and the port should stay on your own network).
FROM node:22-bookworm-slim

# What Electron needs to start, plus a virtual screen and the tools CLIs commonly use.
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb xauth ca-certificates git curl \
      libgtk-3-0 libnss3 libasound2 libgbm1 libxss1 libxtst6 libxkbcommon0 libdrm2 libatk-bridge2.0-0 libcups2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm install --no-save --no-package-lock electron@45.2.1 && node node_modules/electron/install.js
COPY desktop-windows ./desktop-windows
COPY docker ./docker

# AI CLIs are installed by you, so each account stays yours. Pass --build-arg CLIS="@anthropic-ai/claude-code @openai/codex"
# to include some, or install them later inside the running container (see docs/DOCKER.md).
ARG CLIS=""
RUN if [ -n "$CLIS" ]; then npm install -g $CLIS; fi

ENV OPENGROKBOT_DATA_DIR=/data
VOLUME /data
EXPOSE 8765
RUN chmod +x /app/docker/entrypoint.sh && useradd -m -u 1001 grok && mkdir -p /data && chown -R grok /data /app
USER grok
ENTRYPOINT ["/app/docker/entrypoint.sh"]
