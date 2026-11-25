// サーバーの起動。使い方は docs/SERVER.md。
import { config } from "./config.ts";
import { openDb, closeDb, purgeMatchLogs } from "./db.ts";
import { loadStoredSettings } from "./settings.ts";
import { createAdminServer, ADMIN_HOST } from "./admin.ts";
import { Lobby } from "./lobby.ts";
import { createHttpServer, info } from "./http.ts";
import { attachWebSocket } from "./ws.ts";
import { log } from "./log.ts";
import { llmName } from "./llm.ts";
import { applyPendingRestore, startBackupTimer } from "./backup.ts";

// 管理画面で「全部を戻す」を選んでいたら、DB を開く前に入れかえる（要件#131）
applyPendingRestore();
openDb();
// 管理画面で変えた設定を読み込む（環境変数より優先。要件#100）
loadStoredSettings();
startBackupTimer();
const lobby = new Lobby();
const server = createHttpServer(lobby);
const wss = attachWebSocket(server, lobby);
server.listen(config.port, config.host, () => {
  const i = info(lobby);
  log(`cushara-server ${i.version} listening on ${config.host}:${config.port}`);
  log(`AI判定: ${i.ai ? `ON (${llmName()})` : "OFF（キーワード判定）"} / 音声対戦: ${i.voice ? `ON (${config.sttProvider})` : "OFF"}`);
});

// 管理画面（要件#100）。このマシンの中（127.0.0.1）だけで待ち受ける。ADMIN_PORT=0 で使わない
const adminPort = Number(process.env.ADMIN_PORT ?? 8790);
let admin: ReturnType<typeof createAdminServer> | null = null;
if (adminPort > 0) {
  admin = createAdminServer(lobby);
  admin.listen(adminPort, ADMIN_HOST, () => log(`管理画面: http://${ADMIN_HOST}:${adminPort}/ （このマシンの中だけ。家のPCからは SSH のトンネルで）`));
}

// 通報された試合の会話は30日で消す（プライバシーポリシー）
purgeMatchLogs();
setInterval(() => purgeMatchLogs(), 6 * 3_600_000).unref();

// 止めるとき（要件#109）: 新しい接続を断り、今の応答が終わるのを待ってから DB を閉じる。10 秒たっても終わらなければ止める
let stopping = false;
for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => {
    if (stopping) return;
    stopping = true;
    log("shutting down");
    const force = setTimeout(() => {
      closeDb();
      process.exit(0);
    }, 10_000);
    force.unref();
    wss.clients.forEach((c) => c.close(1001, "server shutting down"));
    const closeHttp = new Promise<void>((r) => server.close(() => r()));
    const closeAdmin = admin ? new Promise<void>((r) => admin!.close(() => r())) : Promise.resolve();
    server.closeIdleConnections();
    void Promise.all([closeHttp, closeAdmin]).then(() => {
      closeDb();
      process.exit(0);
    });
  });
}
