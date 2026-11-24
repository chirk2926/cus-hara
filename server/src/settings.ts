// 管理画面で変えられるサーバーの設定（要件#100）。
// 起動時は今までどおり環境変数（config.ts）から読み、管理画面で変えた値を DB（settings 表）から上書きする。
// API キーなどの秘密の値は DB に入れず、var/secrets.json（このファイルの持ち主だけが読める）に置く。
// 秘密の値は管理画面にも全部は出さない（最初と最後の数文字だけ）。
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import { storedSettings, storeSetting } from "./db.ts";
import { resetLlmClient } from "./llm.ts";
import { type AiSlot, type Mode, type Provider, type StoredSlots, PROVIDERS, PROVIDER_INFO, MAX_SLOTS, aiSlots, allSlots, versusSame, isStored, setStoredSlots, setSlotKey, slotKey, slotHealth, usedToday, resetSlotHealth, newSlotId, clearSlotKeys } from "./ai_slots.ts";

export type SettingType = "string" | "number" | "bool" | "enum" | "secret" | "text";

export interface SettingDef {
  key: string;
  group: string;
  label: string;
  help: string;
  type: SettingType;
  options?: string[];
  suggestions?: string[];
  min?: number;
  max?: number;
  /** 変えたあと、サーバーの再起動が必要 */
  restart?: boolean;
  /** config の中の場所（"versus.openingSec" など）。秘密の値は env の名前 */
  path?: string;
  env?: string;
}

// ---------------------------------------------------------------- 実行中だけの設定（config.ts にないもの）

/** メンテナンス中は対戦（マッチング・部屋）を受け付けない。1人用は遊べる */
export const runtime = {
  maintenance: false,
  maintenanceMessage: "",
  statusNote: "",
  /** コンビニを開けるか（要件#102: 準備ができるまで閉じておく）。閉じている間は対戦の舞台にも使わない */
  konbiniOpen: process.env.KONBINI_OPEN === "1",
  /** 1人用の「キレるまでの秒数」（要件#106）。怒り 0 から 100 まで、気の長さふつうのお客さんの1人目。返事の時間の設定ごと */
  snapSlow: 300,
  snapNormal: 180,
  snapFast: 128,
  /** 不適切な発言で負けになる回数 */
  modMax: 3,
  /** AI の料金の目安（1M トークンあたりのドル）。モデル名 → [入力, 出力, キャッシュ読み, キャッシュ書き] */
  aiPrices: {
    "claude-haiku-5-5": [0.1, 0.5, 0.01, 0.125],
    "claude-sonnet-5-5": [2, 10, 0.1, 2.5],
    "claude-opus-5-5": [4, 20, 0.2, 5],
  } as Record<string, [number, number, number, number]>,
  /** ひと月の AI 料金の目安の上限（ドル）。超えそうなら管理画面に警告。0 = 見ない */
  monthlyBudgetUsd: 0,
};

export const SETTINGS: SettingDef[] = [
  // AI
  { key: "llmMode", group: "AI", label: "AIを使うか", help: "auto = 登録した API があれば使う / claude = 必ず使う / offline = 使わない（キーワード判定）。API は「AIのAPI」の画面で登録する", type: "enum", options: ["auto", "claude", "offline"], path: "llmMode" },
  { key: "llmTimeoutMs", group: "AI", label: "AIの応答を待つ時間（ミリ秒）", help: "これを過ぎたらキーワード判定に切り替える。ゲームは35秒で待つのをやめるので、25秒まで", type: "number", min: 3000, max: 25000, path: "llmTimeoutMs" },
  // 音声
  { key: "sttProvider", group: "音声の文字起こし", label: "文字起こしの種類", help: "none = 声の対戦なし / whisper_cpp / openai_compatible / mock（テスト用）", type: "enum", options: ["none", "whisper_cpp", "openai_compatible", "mock"], path: "sttProvider" },
  { key: "sttUrl", group: "音声の文字起こし", label: "文字起こしの場所", help: "例 http://127.0.0.1:8080", type: "string", path: "sttUrl" },
  { key: "sttModel", group: "音声の文字起こし", label: "文字起こしのモデル", help: "openai_compatible のとき（例 whisper-1）", type: "string", path: "sttModel" },
  { key: "STT_API_KEY", group: "音声の文字起こし", label: "文字起こしの APIキー", help: "openai_compatible のとき", type: "secret", env: "STT_API_KEY" },
  { key: "sttTimeoutMs", group: "音声の文字起こし", label: "文字起こしを待つ時間（ミリ秒）", help: "", type: "number", min: 3000, max: 120000, path: "sttTimeoutMs" },
  // 上限・乱用対策
  { key: "llmPerMinute", group: "上限・乱用対策", label: "1人の AI の呼び出し（1分あたり）", help: "超えたらその人はキーワード判定", type: "number", min: 1, max: 600, path: "llmPerMinute" },
  { key: "llmGlobalPerMinute", group: "上限・乱用対策", label: "サーバー全体の AI の呼び出し（1分あたり）", help: "料金を守る上限", type: "number", min: 1, max: 100000, path: "llmGlobalPerMinute" },
  { key: "soloMaxTurns", group: "上限・乱用対策", label: "1人用: 1人のお客さんとのやりとりの上限", help: "", type: "number", min: 5, max: 200, path: "soloMaxTurns" },
  { key: "guestsPerHour", group: "上限・乱用対策", label: "1つの IP が1時間に作れるアカウント", help: "", type: "number", min: 1, max: 10000, path: "guestsPerHour" },
  { key: "wsPerIp", group: "上限・乱用対策", label: "1つの IP の同時接続", help: "Cloudflare Tunnel では TRUST_PROXY=1 にして本当の IP で数える", type: "number", min: 1, max: 1000, path: "wsPerIp" },
  { key: "modMax", group: "上限・乱用対策", label: "不適切な発言で負けになる回数", help: "対戦の中で、この回数で負け", type: "number", min: 1, max: 20, path: "runtime.modMax" },
  { key: "allowSameIpRanked", group: "上限・乱用対策", label: "同じ回線どうしのランクマッチを許す", help: "ふつうはオフ（チート対策）。テストのときだけオン", type: "bool", path: "allowSameIpRanked" },
  { key: "samePairLimit24h", group: "上限・乱用対策", label: "同じ相手とのランクマッチ（24時間）", help: "これを超えるとレーティングが動かない", type: "number", min: 1, max: 100, path: "samePairLimit24h" },
  { key: "allowRankedRooms", group: "上限・乱用対策", label: "EOS で組んだ相手とのランクマッチ", help: "", type: "bool", path: "allowRankedRooms" },
  { key: "rankedRoomMaxGap", group: "上限・乱用対策", label: "EOS のランクの部屋のレーティング差の上限", help: "", type: "number", min: 0, max: 3000, path: "rankedRoomMaxGap" },
  // 対戦
  { key: "versus.openingSec", group: "対戦のルール", label: "最初のクレームの時間（秒）", help: "", type: "number", min: 10, max: 300, path: "versus.openingSec" },
  { key: "versus.customerSec", group: "対戦のルール", label: "客役の番の時間（秒）", help: "", type: "number", min: 10, max: 300, path: "versus.customerSec" },
  { key: "versus.voiceExtraSec", group: "対戦のルール", label: "声の対戦の追加の時間（秒）", help: "", type: "number", min: 0, max: 120, path: "versus.voiceExtraSec" },
  { key: "versus.maxExchanges", group: "対戦のルール", label: "1ラウンドのやりとりの上限", help: "", type: "number", min: 2, max: 40, path: "versus.maxExchanges" },
  { key: "versus.baseAngerRate", group: "対戦のルール", label: "店員の番で怒りが上がる速さ", help: "1秒あたり", type: "number", min: 0.1, max: 5, path: "versus.baseAngerRate" },
  { key: "versus.reconnectGraceMs", group: "対戦のルール", label: "切断から負けまでの猶予（ミリ秒）", help: "", type: "number", min: 0, max: 300000, path: "versus.reconnectGraceMs" },
  { key: "match.startWindow", group: "マッチング", label: "最初に組めるレーティング差", help: "", type: "number", min: 0, max: 3000, path: "match.startWindow" },
  { key: "match.growPerSec", group: "マッチング", label: "1秒ごとに広げる差", help: "", type: "number", min: 0, max: 500, path: "match.growPerSec" },
  { key: "match.anyoneAfterSec", group: "マッチング", label: "誰とでも組むまでの秒数", help: "", type: "number", min: 0, max: 600, path: "match.anyoneAfterSec" },
  // 運営
  { key: "maintenance", group: "運営", label: "メンテナンス中（対戦を止める）", help: "オンの間はマッチング・部屋づくりを受け付けない。1人用は遊べる", type: "bool", path: "runtime.maintenance" },
  { key: "snapSlow", group: "1人用", label: "キレるまでの秒数（かめ・イージー）", help: "怒り 0 から 100 になるまでの秒数。気の長さがふつうのお客さんの1人目の目安（2人目からは少しずつ短くなる）。サーバーにつないでいるゲームにだけ効く", type: "number", min: 30, max: 900, path: "runtime.snapSlow" },
  { key: "snapNormal", group: "1人用", label: "キレるまでの秒数（うさぎ・ノーマル）", help: "同上", type: "number", min: 30, max: 900, path: "runtime.snapNormal" },
  { key: "snapFast", group: "1人用", label: "キレるまでの秒数（チーター・ハード）", help: "同上", type: "number", min: 30, max: 900, path: "runtime.snapFast" },
  { key: "konbiniOpen", group: "運営", label: "コンビニを開ける", help: "オフの間は、ゲームのコンビニが「準備中」になり、対戦の舞台もゲームセンターだけになる", type: "bool", path: "runtime.konbiniOpen" },
  { key: "statusNote", group: "運営", label: "サーバーの状況のお知らせ（紹介サイト）", help: "紹介サイトの「サーバーの状況」のページに、そのまま出す（例: 「AIの調子が悪く、台本のお客さんになることがあります」）。キーやエラーの中身は書かない。空なら出さない", type: "text", path: "runtime.statusNote" },
  { key: "maintenanceMessage", group: "運営", label: "メンテナンス中のお知らせ", help: "ゲームのタイトル画面と、対戦を始めようとした人に出す", type: "text", path: "runtime.maintenanceMessage" },
  { key: "monthlyBudgetUsd", group: "運営", label: "AI料金の目安の上限（ドル/月）", help: "超えそうなら管理画面に警告。0 = 見ない", type: "number", min: 0, max: 1000000, path: "runtime.monthlyBudgetUsd" },
  { key: "aiPrices", group: "運営", label: "AIの料金表（1Mトークンあたりのドル）", help: "{\"モデル名\": [入力, 出力, キャッシュ読み, キャッシュ書き]}。Anthropic の料金ページで確かめて直す", type: "text", path: "runtime.aiPrices" },
  // サーバー（再起動が必要）
  { key: "port", group: "サーバー（再起動が必要）", label: "ゲームのポート", help: "Cloudflare Tunnel の向き先と合わせる", type: "number", min: 1, max: 65535, restart: true, path: "port" },
  { key: "host", group: "サーバー（再起動が必要）", label: "ゲームの待ち受け", help: "Cloudflare Tunnel だけで公開するなら 127.0.0.1", type: "string", restart: true, path: "host" },
];

const BY_KEY = new Map(SETTINGS.map((d) => [d.key, d]));

function target(p: string): { obj: Record<string, unknown>; prop: string } {
  const parts = p.split(".");
  let obj: Record<string, unknown> = parts[0] === "runtime" ? (runtime as never) : (config as never);
  const rest = parts[0] === "runtime" ? parts.slice(1) : parts;
  for (const k of rest.slice(0, -1)) obj = obj[k] as Record<string, unknown>;
  return { obj, prop: rest[rest.length - 1] };
}

// ---------------------------------------------------------------- 秘密の値（var/secrets.json）

function secretsPath(): string | null {
  if (process.env.ADMIN_SECRETS_PATH) return process.env.ADMIN_SECRETS_PATH;
  if (config.dbPath === ":memory:") return null;
  return path.join(path.dirname(config.dbPath), "secrets.json");
}

function readSecrets(): Record<string, string> {
  const p = secretsPath();
  if (!p || !fs.existsSync(p)) return {};
  try {
    return JSON.parse(fs.readFileSync(p, "utf-8")) as Record<string, string>;
  } catch {
    return {};
  }
}

function writeSecrets(s: Record<string, string>): void {
  const p = secretsPath();
  if (!p) return;
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(s, null, 2), { mode: 0o600 });
  fs.chmodSync(p, 0o600);
}

function applySecret(env: string, value: string): void {
  if (value === "") delete process.env[env];
  else process.env[env] = value;
  if (env === "STT_API_KEY") config.sttApiKey = value;
}

/** 最初と最後の数文字だけ見せる */
export function mask(v: string): string {
  if (v === "") return "";
  if (v.length <= 10) return "••••";
  return `${v.slice(0, 6)}••••${v.slice(-4)}`;
}

// ---------------------------------------------------------------- 読み・書き

export function currentValue(d: SettingDef): unknown {
  if (d.type === "secret") return process.env[d.env ?? d.key] ?? (d.env === "STT_API_KEY" ? config.sttApiKey : "");
  const { obj, prop } = target(d.path ?? d.key);
  return obj[prop];
}

/** 管理画面に出す一覧（秘密の値は隠す） */
export function listSettings() {
  return SETTINGS.map((d) => {
    const v = currentValue(d);
    return { ...d, value: d.type === "secret" ? mask(String(v ?? "")) : d.key === "aiPrices" ? JSON.stringify(v) : v, is_set: d.type === "secret" ? String(v ?? "") !== "" : undefined };
  });
}

export class SettingError extends Error {}

/** 型と範囲を確かめて値にする */
function parse(d: SettingDef, raw: unknown): unknown {
  switch (d.type) {
    case "bool":
      if (typeof raw === "boolean") return raw;
      if (raw === "true" || raw === "1") return true;
      if (raw === "false" || raw === "0") return false;
      throw new SettingError("オン・オフで指定してください");
    case "number": {
      const n = typeof raw === "number" ? raw : Number(raw);
      if (!Number.isFinite(n)) throw new SettingError("数で入れてください");
      if ((d.min !== undefined && n < d.min) || (d.max !== undefined && n > d.max)) throw new SettingError(`${d.min}〜${d.max} の範囲で入れてください`);
      return n;
    }
    case "enum":
      if (typeof raw !== "string" || !(d.options ?? []).includes(raw)) throw new SettingError(`次のどれかにしてください: ${(d.options ?? []).join(", ")}`);
      return raw;
    case "secret":
    case "string":
    case "text": {
      // 料金表は保存するとき・記録から戻すときはオブジェクトのまま来る（レビュー1-4: 再起動で消え、「前に戻す」も失敗していた）
      if (d.key === "aiPrices" && typeof raw === "object" && raw !== null) raw = JSON.stringify(raw);
      if (typeof raw !== "string") throw new SettingError("文字で入れてください");
      const v = raw.replace(/[\u0000-\u0008\u000b-\u001f]/g, "").trim();
      if (v.length > (d.type === "text" ? 2000 : 500)) throw new SettingError("長すぎます");
      if (d.key === "aiPrices") {
        let o: unknown;
        try {
          o = JSON.parse(v);
        } catch {
          throw new SettingError("JSON の形が正しくありません");
        }
        if (typeof o !== "object" || o === null || Array.isArray(o)) throw new SettingError("{\"モデル名\": [入力, 出力, キャッシュ読み, キャッシュ書き]} の形にしてください");
        for (const [k, a] of Object.entries(o as Record<string, unknown>)) {
          if (!Array.isArray(a) || a.length !== 4 || a.some((x) => typeof x !== "number" || x < 0)) throw new SettingError(`${k}: 4つの数（0以上）にしてください`);
        }
        return o;
      }
      if (d.key === "sttUrl" && v !== "") checkApiUrl(v);
      return v;
    }
  }
}

/**
 * 設定を変える。戻り値は変える前と後（記録用。秘密の値は隠したもの）
 * persist = false は起動時の読み込み（記録しない）
 */
export function setSetting(key: string, raw: unknown, persist = true): { before: string; after: string; restart: boolean } {
  const d = BY_KEY.get(key);
  if (!d) throw new SettingError("その設定はありません");
  const v = parse(d, raw);
  const beforeRaw = currentValue(d);
  const show = (x: unknown) => (d.type === "secret" ? mask(String(x ?? "")) : typeof x === "object" ? JSON.stringify(x) : String(x));
  if (d.type === "secret") {
    applySecret(d.env ?? d.key, v as string);
    if (persist) {
      const s = readSecrets();
      if (v === "") delete s[d.env ?? d.key];
      else s[d.env ?? d.key] = v as string;
      writeSecrets(s);
    }
  } else {
    const { obj, prop } = target(d.path ?? d.key);
    obj[prop] = v;
    if (persist) storeSetting(key, JSON.stringify(v));
  }
  if (d.group === "AI") resetLlmClient();
  return { before: show(beforeRaw), after: show(currentValue(d)), restart: d.restart === true };
}

/** 起動時: 管理画面で変えた値を読み込む（環境変数より優先） */
/** 外の API の場所として使ってよい URL か（要件#108: クラウドのメタデータの住所などには送らない） */
export function checkApiUrl(v: string): void {
  if (!/^https?:\/\/[^\s]+$/.test(v)) throw new SettingError("http:// か https:// で始まる URL にしてください");
  const host = (() => { try { return new URL(v).hostname.toLowerCase(); } catch { return ""; } })();
  if (host === "" || /^169\.254\./.test(host) || host === "metadata.google.internal" || host === "[fd00:ec2::254]" || host === "100.100.100.200") throw new SettingError("その住所には送れません");
}

/** 前の版で管理画面から変えた AI の設定（1つだけの API）。登録の画面でまだ保存していないときは、これを使う */
const LEGACY_AI: Record<string, (v: unknown) => void> = {
  llmProvider: (v) => { if (v === "anthropic" || v === "openai_compatible") config.llmProvider = v; },
  model: (v) => { if (typeof v === "string" && v !== "") config.model = v; },
  llmBaseUrl: (v) => { if (typeof v === "string") config.llmBaseUrl = v; },
  llmModel: (v) => { if (typeof v === "string") config.llmModel = v; },
  llmJsonMode: (v) => { if (v === "json_schema" || v === "json_object") config.llmJsonMode = v; },
};

export function loadStoredSettings(): void {
  const st = storedSettings();
  for (const [k, raw] of Object.entries(st)) {
    if (k === AI_SLOTS_KEY) continue;
    if (k in LEGACY_AI) {
      try { LEGACY_AI[k](JSON.parse(raw)); } catch { /* 壊れた値は無視 */ }
      continue;
    }
    try {
      setSetting(k, JSON.parse(raw), false);
    } catch {
      // 古い・壊れた値は無視する（環境変数の値のまま）
    }
  }
  const secrets = readSecrets();
  for (const [env, v] of Object.entries(secrets)) {
    if (SETTINGS.some((d) => d.type === "secret" && (d.env ?? d.key) === env)) applySecret(env, v);
    // 前の版の Claude・OpenAI 互換のキー（登録の画面でまだ保存していないとき、環境変数から作る登録が使う）
    if (env === "ANTHROPIC_API_KEY" || env === "LLM_API_KEY") applySecret(env, v);
  }
  // AI の API の登録（要件#115）
  clearSlotKeys();
  setStoredSlots(null);
  if (st[AI_SLOTS_KEY] !== undefined) {
    try {
      setStoredSlots(sanitizeStored(JSON.parse(st[AI_SLOTS_KEY])));
      for (const [env, v] of Object.entries(secrets)) if (env.startsWith(SLOT_KEY_PREFIX)) setSlotKey(env.slice(SLOT_KEY_PREFIX.length), v);
    } catch {
      setStoredSlots(null);
    }
  }
  resetLlmClient();
}

// ---------------------------------------------------------------- AI の API の登録（要件#115, #116）

const AI_SLOTS_KEY = "aiSlots";
const SLOT_KEY_PREFIX = "AI_KEY_";
const MODEL_RE = /^[A-Za-z0-9._:/@+-]{1,100}$/;
const MODES: Mode[] = ["solo", "versus"];
const MODE_LABEL: Record<Mode, string> = { solo: "1人用", versus: "対戦" };

function sanitizeList(v: unknown): AiSlot[] {
  if (!Array.isArray(v)) return [];
  const out: AiSlot[] = [];
  for (const x of v.slice(0, MAX_SLOTS)) {
    const o = (x ?? {}) as Record<string, unknown>;
    if (typeof o.id !== "string" || !/^[0-9a-f]{8}$/.test(o.id) || !PROVIDERS.includes(o.provider as Provider)) continue;
    out.push({
      id: o.id, enabled: o.enabled !== false, provider: o.provider as Provider,
      model: typeof o.model === "string" && MODEL_RE.test(o.model) ? o.model : "",
      genModel: typeof o.genModel === "string" && MODEL_RE.test(o.genModel) ? o.genModel : "",
      dailyLimit: Number.isInteger(o.dailyLimit) && (o.dailyLimit as number) > 0 ? Math.min(1_000_000, o.dailyLimit as number) : 0,
      label: typeof o.label === "string" ? o.label.replace(/[\u0000-\u001f\u007f<>]/g, "").slice(0, 40) : "",
      baseUrl: typeof o.baseUrl === "string" ? o.baseUrl : "",
      jsonMode: o.jsonMode === "json_object" ? "json_object" : "json_schema",
    });
  }
  return out;
}

/** 保存した登録を読む。前の版（1人用の並びだけの配列）も読める */
function sanitizeStored(v: unknown): StoredSlots {
  if (Array.isArray(v)) return { solo: sanitizeList(v), versus: [], versusSame: true };
  const o = (v ?? {}) as Record<string, unknown>;
  return { solo: sanitizeList(o.solo), versus: sanitizeList(o.versus), versusSame: o.versusSame !== false };
}

function currentStored(): StoredSlots {
  if (isStored()) {
    const same = versusSame();
    return { solo: aiSlots("solo"), versus: same ? [] : aiSlots("versus"), versusSame: same };
  }
  // まだ保存していない: 環境変数から作った登録を1人用に（新しい id にする）。対戦は1人用と同じ
  return { solo: aiSlots("solo"), versus: [], versusSame: true };
}

/** 管理画面に返す登録の一覧。キーは最初と最後の数文字だけ */
export function aiSlotsForAdmin() {
  const view = (s: AiSlot) => {
    const k = slotKey(s);
    return {
      id: s.id, enabled: s.enabled, provider: s.provider, model: s.model, gen_model: s.genModel, daily_limit: s.dailyLimit, label: s.label,
      base_url: s.baseUrl, json_mode: s.jsonMode, key_set: k !== "", key_mask: mask(k), used_today: usedToday(s.id), ...slotHealth(s.id),
    };
  };
  const same = versusSame();
  return {
    saved: isStored(),
    max: MAX_SLOTS,
    versus_same: same,
    providers: PROVIDERS.map((p) => ({ id: p, label: PROVIDER_INFO[p].label, models: PROVIDER_INFO[p].models, needs_url: p === "custom" })),
    solo: aiSlots("solo").map(view),
    versus: same ? [] : aiSlots("versus").map(view),
  };
}

function validateList(input: unknown, mode: Mode, before: Map<string, AiSlot>, keys: Map<string, string>): AiSlot[] {
  if (!Array.isArray(input)) throw new SettingError("登録の形が正しくありません");
  if (input.length > MAX_SLOTS) throw new SettingError(`${MODE_LABEL[mode]}: 登録できるのは ${MAX_SLOTS} 個までです`);
  const out: AiSlot[] = [];
  for (const [i, x] of input.entries()) {
    const o = (x ?? {}) as Record<string, unknown>;
    const at = `${MODE_LABEL[mode]} ${i + 1}位`;
    if (!PROVIDERS.includes(o.provider as Provider)) throw new SettingError(`${at}: AIの種類を選んでください`);
    const provider = o.provider as Provider;
    const model = typeof o.model === "string" ? o.model.trim() : "";
    if (!MODEL_RE.test(model)) throw new SettingError(`${at}: モデル名を入れてください（英数字と . _ : / - だけ）`);
    const genModel = typeof o.gen_model === "string" ? o.gen_model.trim() : "";
    if (genModel !== "" && !MODEL_RE.test(genModel)) throw new SettingError(`${at}: お客さんづくりのモデル名は英数字と . _ : / - だけにしてください`);
    const dl = Number(o.daily_limit ?? 0);
    if (!Number.isFinite(dl) || dl < 0 || dl > 1_000_000 || Math.floor(dl) !== dl) throw new SettingError(`${at}: 1日の上限は 0（上限なし）か、1〜1000000 の整数にしてください`);
    const label = typeof o.label === "string" ? o.label.replace(/[\u0000-\u001f\u007f<>]/g, "").trim().slice(0, 40) : "";
    let baseUrl = "";
    if (provider === "custom") {
      baseUrl = typeof o.base_url === "string" ? o.base_url.trim() : "";
      if (baseUrl === "") throw new SettingError(`${at}: API の場所（URL）を入れてください`);
      if (baseUrl.length > 300) throw new SettingError(`${at}: URL が長すぎます`);
      checkApiUrl(baseUrl);
    }
    // 前からある登録はその id のまま（環境変数から作った登録は、保存したときに新しい id にする）
    const oldId = typeof o.id === "string" ? o.id : "";
    const old = before.get(oldId);
    const id = old && /^[0-9a-f]{8}$/.test(oldId) && !out.some((y) => y.id === oldId) ? oldId : newSlotId();
    const key = typeof o.key === "string" ? o.key.replace(/[\u0000-\u001f\u007f\s]/g, "") : "";
    if (key.length > 500) throw new SettingError(`${at}: キーが長すぎます`);
    // キー: 入れたらそれ、「消す」なら無し、どちらでもなければ前のまま。copy_key_from は写したときの元の登録
    const from = typeof o.copy_key_from === "string" ? before.get(o.copy_key_from) : undefined;
    if (key !== "") keys.set(id, key);
    else if (o.clear_key !== true && (old || from)) {
      const k = slotKey((old ?? from)!);
      if (k !== "") keys.set(id, k);
    }
    // 種類・モデル・場所・キーを変えたら、失敗の回数を消してすぐに使ってみる
    if (!old || old.provider !== provider || old.model !== model || old.genModel !== genModel || old.baseUrl !== baseUrl || key !== "") resetSlotHealth(id);
    out.push({ id, enabled: o.enabled !== false, provider, model, genModel, dailyLimit: dl, label, baseUrl, jsonMode: o.json_mode === "json_object" ? "json_object" : "json_schema" });
  }
  return out;
}

/**
 * 登録を保存する（並び順がそのまま優先順位）。body: {solo: [...], versus: [...], versus_same: bool}。
 * 送らなかったモードは前のまま。各行: {id?, enabled, provider, model, gen_model, daily_limit, label, base_url, json_mode, key?（入れたときだけ変える）, clear_key?, copy_key_from?}
 * 戻り値は記録用の短い説明（キーは入れない）
 */
export function saveAiSlots(body: Record<string, unknown>): string {
  const cur = currentStored();
  const before = new Map(allSlots().map((s) => [s.id, s]));
  const keys = new Map<string, string>();
  const next: StoredSlots = { ...cur };
  for (const m of MODES) {
    if (body[m] !== undefined) next[m] = validateList(body[m], m, before, keys);
    else for (const s of cur[m]) { const k = slotKey(s); if (k !== "") keys.set(s.id, k); }
  }
  if (typeof body.versus_same === "boolean") next.versusSame = body.versus_same;
  if (next.versusSame) next.versus = [];
  // 1人用と対戦で同じ id を使わない（飛ばす回数・1日の回数を分けて数える）
  const soloIds = new Set(next.solo.map((s) => s.id));
  if (next.versus.some((s) => soloIds.has(s.id))) throw new SettingError("1人用と対戦で同じ登録は使えません（写すボタンを使ってください）");
  // 保存: 並びは DB、キーは secrets.json（使わなくなった登録のキーは消す）
  const live = new Set([...next.solo, ...next.versus].map((s) => s.id));
  const secrets = readSecrets();
  for (const k of Object.keys(secrets)) if (k.startsWith(SLOT_KEY_PREFIX)) delete secrets[k];
  for (const [id, k] of keys) if (live.has(id)) secrets[SLOT_KEY_PREFIX + id] = k;
  writeSecrets(secrets);
  storeSetting(AI_SLOTS_KEY, JSON.stringify(next));
  clearSlotKeys();
  for (const [id, k] of keys) if (live.has(id)) setSlotKey(id, k);
  setStoredSlots(next);
  resetLlmClient();
  const desc = (list: AiSlot[]) => list.map((s, i) => `${i + 1}位 ${PROVIDER_INFO[s.provider].label} ${s.model}${s.enabled ? "" : "（休止）"}${keys.has(s.id) || s.provider === "custom" ? "" : "（キーなし）"}`).join(" / ") || "登録なし";
  return `1人用: ${desc(next.solo)}｜対戦: ${next.versusSame ? "1人用と同じ" : desc(next.versus)}`;
}

/** 1人用の並びを対戦に写す（キーも。新しい id にする） */
export function copySoloToVersus(): string {
  const solo = aiSlots("solo");
  return saveAiSlots({
    versus_same: false,
    versus: solo.map((s) => ({ provider: s.provider, model: s.model, gen_model: s.genModel, daily_limit: s.dailyLimit, label: s.label, base_url: s.baseUrl, json_mode: s.jsonMode, enabled: s.enabled, copy_key_from: s.id })),
  });
}

/** 戻す（記録の「変える前」の値に）。秘密の値は戻せない（記録に残していないため） */
export function settingDef(key: string): SettingDef | undefined {
  return BY_KEY.get(key);
}

/** AI の料金の目安（ドル） */
export function costUsd(model: string, u: { input: number; output: number; cache_read: number; cache_write: number }): number {
  const p = runtime.aiPrices[model] ?? Object.entries(runtime.aiPrices).find(([k]) => model.startsWith(k))?.[1];
  if (!p) return 0;
  return (u.input * p[0] + u.output * p[1] + u.cache_read * p[2] + u.cache_write * p[3]) / 1_000_000;
}
