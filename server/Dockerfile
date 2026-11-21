# ゲームサーバーのコンテナ。リポジトリのルートでビルドする:
#   docker build -f server/Dockerfile -t cushara-server .
FROM node:22.20.0-bookworm-slim
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev
COPY server/src ./src
COPY server/public ./public
COPY server/admin ./admin
COPY data /app/data
ENV NODE_ENV=production \
    PORT=8787 \
    DB_PATH=/var/lib/cushara/cushara.db \
    SCENARIOS_PATH=/app/data/scenarios.json \
    ADMIN_PORT=0
# 管理画面はコンテナの中の 127.0.0.1 でしか待たないので、コンテナでは止めておく（要件#108）。
# 管理画面を使うなら、docs/HOME_SERVER.md のように systemd で動かす
RUN mkdir -p /var/lib/cushara && chown node:node /var/lib/cushara
USER node
EXPOSE 8787
CMD ["node", "--disable-warning=ExperimentalWarning", "src/main.ts"]
