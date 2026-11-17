// サーバーの起動。使い方は docs/SERVER.md。
import { config } from "./config.ts";
import { openDb } from "./db.ts";
import { Lobby } from "./lobby.ts";
import { createHttpServer, info } from "./http.ts";
import { attachWebSocket } from "./ws.ts";
import { log } from "./log.ts";

openDb();
const lobby = new Lobby();
const server = createHttpServer(lobby);
attachWebSocket(server, lobby);
server.listen(config.port, config.host, () => {
  const i = info(lobby);
  log(`cushara-server ${i.version} listening on ${config.host}:${config.port}`);
  log(`AI判定: ${i.ai ? `ON (${config.model})` : "OFF（キーワード判定）"} / 音声対戦: ${i.voice ? `ON (${config.sttProvider})` : "OFF"}`);
});

for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => {
    log("shutting down");
    server.close();
    process.exit(0);
  });
}
