// サーバーの起動。使い方は docs/SERVER.md。
import { config } from "./config.ts";
import { openDb, purgeMatchLogs } from "./db.ts";
import { loadStoredSettings } from "./settings.ts";
import { createAdminServer, ADMIN_HOST } from "./admin.ts";
import { Lobby } from "./lobby.ts";
import { createHttpServer, info } from "./http.ts";
import { attachWebSocket } from "./ws.ts";
import { log } from "./log.ts";

openDb();
// 管理画面で変えた設定を読み込む（環境変数より優先。要件#100）
loadStoredSettings();
const lobby = new Lobby();
const server = createHttpServer(lobby);
attachWebSocket(server, lobby);
server.listen(config.port, config.host, () => {
  const i = info(lobby);
  log(`cushara-server ${i.version} listening on ${config.host}:${config.port}`);
  log(`AI判定: ${i.ai ? `ON (${config.model})` : "OFF（キーワード判定）"} / 音声対戦: ${i.voice ? `ON (${config.sttProvider})` : "OFF"}`);
});

// 管理画面（要件#100）。このマシンの中（127.0.0.1）だけで待ち受ける。ADMIN_PORT=0 で使わない
const adminPort = Number(process.env.ADMIN_PORT ?? 8790);
if (adminPort > 0) {
  const admin = createAdminServer(lobby);
  admin.listen(adminPort, ADMIN_HOST, () => log(`管理画面: http://${ADMIN_HOST}:${adminPort}/ （このマシンの中だけ。家のPCからは SSH のトンネルで）`));
}

// 通報された試合の会話は30日で消す（プライバシーポリシー）
purgeMatchLogs();
setInterval(() => purgeMatchLogs(), 6 * 3_600_000).unref();

for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => {
    log("shutting down");
    server.close();
    process.exit(0);
  });
}
