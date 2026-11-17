import { test } from "node:test";
import assert from "node:assert/strict";
process.env.SCENARIOS_PATH ??= new URL("../../data/scenarios.json", import.meta.url).pathname;
const { eloDelta, rankName } = await import("../src/rating.ts");
const { mulawToPcm16, pcm16ToMulaw, wavFromPcm16 } = await import("../src/audio.ts");
const { judgeStaff, judgeCustomerLine } = await import("../src/keyword_judge.ts");
const { allCustomers } = await import("../src/scenarios.ts");

test("Elo: 同じ強さなら ±16、格上に勝つと多く上がる", () => {
  assert.equal(eloDelta(1000, 1000, 1), 16);
  assert.equal(eloDelta(1000, 1000, 0), -16);
  assert.ok(eloDelta(1000, 1400, 1) > 25);
  assert.equal(eloDelta(1000, 1000, 0.5), 0);
});

test("ランク名", () => {
  assert.equal(rankName(1000), "アルバイト");
  assert.equal(rankName(850), "研修生");
  assert.equal(rankName(1750), "伝説のクレーム処理班");
});

test("μ-law の往復でほぼ元に戻る、WAV ヘッダ", () => {
  const pcm = new Int16Array([0, 1000, -1000, 20000, -20000, 32000]);
  const back = mulawToPcm16(pcm16ToMulaw(pcm));
  for (let i = 0; i < pcm.length; i++) assert.ok(Math.abs(back[i] - pcm[i]) <= Math.max(64, Math.abs(pcm[i]) * 0.07));
  const wav = wavFromPcm16(pcm);
  assert.equal(wav.toString("ascii", 0, 4), "RIFF");
  assert.equal(wav.readUInt32LE(24), 16000);
  assert.equal(wav.length, 44 + pcm.length * 2);
});

test("キーワード判定: 正しい対応・屈服・謝罪の誤判定", () => {
  const c = allCustomers("konbini")[0];
  const good = judgeStaff(c, "大変申し訳ございません。すぐに新しいお箸をお持ちいたします。", [], 40, 0);
  assert.ok(good.anger_delta < 0 && good.resolve_delta > 0);
  assert.equal(good.yielded, false);
  const bad = judgeStaff(c, "分かりました、土下座します。", [], 40, 0);
  assert.equal(bad.yielded, true);
  const refuse = judgeStaff(c, "申し訳ございません、土下座はいたしかねます。", [], 40, 0);
  assert.equal(refuse.yielded, false, "断っている文は屈服にならない");
});

test("客役のセリフ判定", () => {
  const c = allCustomers("arcade")[0];
  assert.equal(judgeCustomerLine(c, "", []).resolve_delta, 12);
  assert.equal(judgeCustomerLine(c, "死ね", []).resolve_delta, 15);
  assert.ok(judgeCustomerLine(c, "責任者を出せ！三千円も使ったんだぞ、どうしてくれるんだ！", []).anger_delta >= 8);
});

test("台本データ: すべてのお客さんに必要な項目がある", () => {
  for (const stage of ["konbini", "arcade"] as const) {
    const list = allCustomers(stage);
    assert.ok(list.length >= 8);
    for (const c of list) {
      for (const k of ["title", "name", "memo", "opening", "demand"] as const) assert.ok(c[k].length > 0, `${c.title}.${k}`);
      assert.ok((c.solution_keywords ?? []).length >= 3, c.title);
      assert.ok((c.yield_keywords ?? []).length >= 3, c.title);
      assert.ok(c.patience >= 0.7 && c.patience <= 1.4);
    }
  }
});
