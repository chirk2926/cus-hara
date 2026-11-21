// 管理画面で変えられるサーバーの設定（要件#100）。
// 起動時は今までどおり環境変数（config.ts）から読み、管理画面で変えた値を DB（settings 表）から上書きする。
// API キーなどの秘密の値は DB に入れず、var/secrets.json（このファイルの持ち主だけが読める）に置く。
// 秘密の値は管理画面にも全部は出さない（最初と最後の数文字だけ）。
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import { storedSettings, storeSetting } from "./db.ts";
import { resetLlmClient } from "./llm.ts";

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
  { key: "llmMode", group: "AI", label: "AIを使うか", help: "auto = APIキーがあれば使う / claude = 必ず使う / offline = 使わない（キーワード判定）", type: "enum", options: ["auto", "claude", "offline"], path: "llmMode" },
  { key: "llmProvider", group: "AI", label: "AIの種類", help: "anthropic = Claude / openai_compatible = OpenAI 互換の API（OpenAI・Gemini・DeepSeek・Ollama など）", type: "enum", options: ["anthropic", "openai_compatible"], path: "llmProvider" },
  { key: "model", group: "AI", label: "Claude のモデル", help: "判定・お客さんづくりに使うモデル。Haiku が速くて安い", type: "string", suggestions: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"], path: "model" },
  { key: "ANTHROPIC_API_KEY", group: "AI", label: "Claude の APIキー", help: "Anthropic の Console で作るキー", type: "secret", env: "ANTHROPIC_API_KEY" },
  { key: "llmBaseUrl", group: "AI", label: "OpenAI 互換: API の場所", help: "例 https://api.openai.com/v1 、http://127.0.0.1:11434/v1", type: "string", path: "llmBaseUrl" },
  { key: "llmModel", group: "AI", label: "OpenAI 互換: モデル名", help: "例 gpt-5-mini、llama3", type: "string", path: "llmModel" },
  { key: "LLM_API_KEY", group: "AI", label: "OpenAI 互換: APIキー", help: "Ollama など、キーが要らないものは空のまま", type: "secret", env: "LLM_API_KEY" },
  { key: "llmJsonMode", group: "AI", label: "OpenAI 互換: JSON の出させ方", help: "json_schema に対応していないAIは json_object", type: "enum", options: ["json_schema", "json_object"], path: "llmJsonMode" },
  { key: "llmTimeoutMs", group: "AI", label: "AIの応答を待つ時間（ミリ秒）", help: "これを過ぎたらキーワード判定に切り替える", type: "number", min: 3000, max: 120000, path: "llmTimeoutMs" },
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
      if ((d.key === "llmBaseUrl" || d.key === "sttUrl") && v !== "" && !/^https?:\/\/[^\s]+$/.test(v)) throw new SettingError("http:// か https:// で始まる URL にしてください");
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
export function loadStoredSettings(): void {
  for (const [k, raw] of Object.entries(storedSettings())) {
    try {
      setSetting(k, JSON.parse(raw), false);
    } catch {
      // 古い・壊れた値は無視する（環境変数の値のまま）
    }
  }
  for (const [env, v] of Object.entries(readSecrets())) {
    if (SETTINGS.some((d) => d.type === "secret" && (d.env ?? d.key) === env)) applySecret(env, v);
  }
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
