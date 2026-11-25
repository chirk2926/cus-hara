// 自動バックアップ（要件#131）: 取る・プレイヤーだけ戻す・全部を戻す（次の起動で入れかえる）・残す数
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cushara-backup-"));
process.env.DB_PATH = path.join(dir, "cushara.db");
const db = await import("../src/db.ts");
const bk = await import("../src/backup.ts");
const { runtime } = await import("../src/settings.ts");

test("バックアップを取り、プレイヤーだけ戻し、全部を戻す", () => {
  const { player: a } = db.createPlayer("あいうえお");
  const { player: b } = db.createPlayer("かきくけこ");
  fs.writeFileSync(path.join(dir, "secrets.json"), JSON.stringify({ X: "1" }));
  const id = bk.createBackup("manual");
  assert.equal(bk.listBackups()[0].id, id);
  assert.equal(bk.listBackups()[0].players, 2);
  assert.ok(fs.existsSync(path.join(dir, "backups", id, "secrets.json")));
  // あとから変わった
  db.renamePlayer(a.id, "かわった名前");
  db.renamePlayer(b.id, "べつの名前");
  assert.deepEqual(bk.backupPlayers(id, "あいう").map((p) => p.id), [a.id]);
  // a だけ戻す（b はそのまま）
  bk.restorePlayer(id, a.id);
  assert.equal(db.playerById(a.id)!.name, "あいうえお");
  assert.equal(db.playerById(b.id)!.name, "べつの名前");
  // 消えてしまったプレイヤーも作り直せる
  db.openDb().prepare("DELETE FROM players WHERE id = ?").run(b.id);
  bk.restorePlayer(id, b.id);
  assert.equal(db.playerById(b.id)!.name, "かきくけこ");
  // 全部を戻す: 印を置き、次の起動（applyPendingRestore）で入れかえる。戻す前の写しも取る
  db.renamePlayer(a.id, "また変わった");
  fs.writeFileSync(path.join(dir, "secrets.json"), JSON.stringify({ X: "2" }));
  bk.scheduleFullRestore(id);
  bk.applyPendingRestore();
  assert.equal(db.playerById(a.id)!.name, "あいうえお");
  assert.equal(JSON.parse(fs.readFileSync(path.join(dir, "secrets.json"), "utf-8")).X, "1");
  assert.ok(bk.listBackups().some((x) => x.note === "before-restore"), "戻す前の写しがある");
  assert.ok(!fs.existsSync(path.join(dir, "restore_pending")));
});

test("残す数より古いバックアップは消す", () => {
  runtime.backupKeep = 2;
  for (let i = 0; i < 3; i++) bk.createBackup("manual");
  assert.equal(bk.listBackups().length, 2);
  runtime.backupKeep = 14;
  db.closeDb();
  fs.rmSync(dir, { recursive: true, force: true });
});
