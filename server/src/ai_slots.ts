// AI の API の登録（要件#115）。管理画面から最大5個、優先順位つきで登録する。
// 1位から順に使い、失敗したら次の順位へ。失敗した API はしばらく飛ばす（連続10回目までは5分、
// そこからは1回ごとに5分ずつ延ばして最大60分。成功したら回数は0に戻る）。
// 対応: Claude（Anthropic）・OpenAI・Gemini・DeepSeek・そのほかの OpenAI 互換（Ollama など）。
// キーは var/secrets.json（0600）にだけ置き、管理画面にも最初と最後の数文字しか返さない。
import crypto from "node:crypto";
import { config } from "./config.ts";

export type Provider = "anthropic" | "openai" | "gemini" | "deepseek" | "custom";
export const PROVIDERS: Provider[] = ["anthropic", "openai", "gemini", "deepseek", "custom"];
export const MAX_SLOTS = 5;

export interface ProviderInfo {
  label: string;
  /** OpenAI 互換の API の場所（anthropic は SDK、custom は登録ごとに入れる） */
  baseUrl: string;
  /** モデルの候補（先頭が既定。どれも手で書きかえられる） */
  models: string[];
  /** JSON の出させ方。json_schema = スキーマどおりに出させる / json_object = JSON だけ（スキーマは指示文で伝える） */
  json: "json_schema" | "json_object";
  /** 出力の長さの上限を送る項目の名前（OpenAI の新しいモデルは max_completion_tokens） */
  maxTokensField: "max_tokens" | "max_completion_tokens";
}

export const PROVIDER_INFO: Record<Provider, ProviderInfo> = {
  anthropic: { label: "Claude（Anthropic）", baseUrl: "", models: ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"], json: "json_schema", maxTokensField: "max_tokens" },
  openai: { label: "OpenAI", baseUrl: "https://api.openai.com/v1", models: ["gpt-5-mini", "gpt-5-nano", "gpt-5"], json: "json_schema", maxTokensField: "max_completion_tokens" },
  gemini: { label: "Gemini（Google）", baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai", models: ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro"], json: "json_schema", maxTokensField: "max_tokens" },
  deepseek: { label: "DeepSeek", baseUrl: "https://api.deepseek.com", models: ["deepseek-chat"], json: "json_object", maxTokensField: "max_tokens" },
  custom: { label: "そのほか（OpenAI 互換）", baseUrl: "", models: [], json: "json_schema", maxTokensField: "max_tokens" },
};

/** どのモードで使うか（要件#116: 1人用と対戦で別の並びにできる） */
export type Mode = "solo" | "versus";
/** 何に使うか（generate = お客さんづくり。登録ごとに別のモデルを指定できる） */
export type Purpose = "generate" | "judge";

export interface AiSlot {
  id: string;
  enabled: boolean;
  provider: Provider;
  model: string;
  /** お客さんづくりだけに使うモデル（空なら model。要件#116） */
  genModel: string;
  /** 1日に呼んでよい回数（0 = 上限なし。サーバーの日付で数え、再起動で0に戻る。要件#116） */
  dailyLimit: number;
  /** 管理画面に出すメモ（例: 「予備のキー」） */
  label: string;
  /** custom のときだけ使う */
  baseUrl: string;
  /** custom のときだけ使う */
  jsonMode: "json_schema" | "json_object";
}

export interface StoredSlots {
  solo: AiSlot[];
  versus: AiSlot[];
  /** 対戦も1人用と同じ並びを使う */
  versusSame: boolean;
}

/** 登録（null = まだ管理画面で保存していない → 環境変数から作る） */
let stored: StoredSlots | null = null;
/** キー（id → キー）。保存のときは secrets.json にも書く */
const keys = new Map<string, string>();

export function setStoredSlots(slots: StoredSlots | null): void {
  stored = slots;
}

export function setSlotKey(id: string, key: string): void {
  if (key === "") keys.delete(id);
  else keys.set(id, key);
}

export function slotKey(slot: AiSlot): string {
  if (keys.has(slot.id)) return keys.get(slot.id)!;
  // 環境変数から作った登録は、環境変数のキーを使う
  return slot.id.startsWith("env-") ? process.env[ENV_KEY[slot.provider]] ?? "" : "";
}

export function clearSlotKeys(): void {
  keys.clear();
}

const ENV_KEY: Record<Provider, string> = {
  anthropic: "ANTHROPIC_API_KEY", openai: "OPENAI_API_KEY", gemini: "GEMINI_API_KEY", deepseek: "DEEPSEEK_API_KEY", custom: "LLM_API_KEY",
};

/**
 * 管理画面でまだ登録していないとき: 環境変数から作る（今までの設定のまま動くように）。
 * 順番は、LLM_PROVIDER=openai_compatible の API → Claude → OpenAI → Gemini → DeepSeek
 */
function envSlots(): AiSlot[] {
  const out: AiSlot[] = [];
  if (config.llmProvider === "openai_compatible" && config.llmBaseUrl !== "" && config.llmModel !== "") {
    out.push({ id: "env-custom", enabled: true, provider: "custom", model: config.llmModel, baseUrl: config.llmBaseUrl, jsonMode: config.llmJsonMode === "json_object" ? "json_object" : "json_schema", genModel: "", dailyLimit: 0, label: "" });
  }
  if (process.env.ANTHROPIC_API_KEY || (config.llmMode === "claude" && config.llmProvider !== "openai_compatible")) {
    out.push({ id: "env-anthropic", enabled: true, provider: "anthropic", model: config.model, baseUrl: "", jsonMode: "json_schema", genModel: "", dailyLimit: 0, label: "" });
  }
  for (const p of ["openai", "gemini", "deepseek"] as const) {
    if (process.env[ENV_KEY[p]]) {
      const m = process.env[`${p.toUpperCase()}_MODEL`] ?? PROVIDER_INFO[p].models[0];
      out.push({ id: `env-${p}`, enabled: true, provider: p, model: m, baseUrl: "", jsonMode: "json_schema", genModel: "", dailyLimit: 0, label: "" });
    }
  }
  return out.slice(0, MAX_SLOTS);
}

/** そのモードの登録の一覧（優先順位の順）。対戦が「1人用と同じ」なら1人用の並び */
export function aiSlots(mode: Mode = "solo"): AiSlot[] {
  if (stored === null) return envSlots();
  return mode === "versus" && !stored.versusSame ? stored.versus : stored.solo;
}

/** 対戦も1人用と同じ並びを使うか */
export function versusSame(): boolean {
  return stored === null || stored.versusSame;
}

/** 両方のモードの登録（同じ id は1つ） */
export function allSlots(): AiSlot[] {
  if (stored === null) return envSlots();
  const seen = new Set<string>();
  return [...stored.solo, ...stored.versus].filter((x) => (seen.has(x.id) ? false : (seen.add(x.id), true)));
}

export function isStored(): boolean {
  return stored !== null;
}

/** 使える状態か（有効で、キーがある。custom は場所があればキーなしでもよい） */
export function slotUsable(s: AiSlot): boolean {
  if (!s.enabled || s.model === "") return false;
  if (s.provider === "custom") return s.baseUrl !== "";
  // Claude の「必ず使う」（テスト用の偽のサーバーなど）はキーがなくても試す
  if (s.provider === "anthropic" && s.id === "env-anthropic" && config.llmMode === "claude") return true;
  return slotKey(s) !== "";
}

export function newSlotId(): string {
  return crypto.randomBytes(4).toString("hex");
}

// ---------------------------------------------------------------- 1日の上限（要件#116）

const daily = new Map<string, { day: string; n: number }>();
const today = (now = Date.now()) => new Date(now).toISOString().slice(0, 10);

/** 今日この登録を呼んだ回数 */
export function usedToday(id: string, now = Date.now()): number {
  const d = daily.get(id);
  return d && d.day === today(now) ? d.n : 0;
}

export function countUse(id: string, now = Date.now()): void {
  const t = today(now);
  const d = daily.get(id);
  if (d && d.day === t) d.n++;
  else daily.set(id, { day: t, n: 1 });
}

/** 今日の上限に達したか */
export function overDaily(s: AiSlot, now = Date.now()): boolean {
  return s.dailyLimit > 0 && usedToday(s.id, now) >= s.dailyLimit;
}

// ---------------------------------------------------------------- 失敗したら飛ばす

interface Health {
  fails: number;
  until: number;
  lastFailAt: number;
}
const health = new Map<string, Health>();

/** 連続 n 回目の失敗で飛ばす分数: 10回目までは5分、そこから1回ごとに5分ずつ延ばして最大60分 */
export function skipMinutes(n: number): number {
  if (n <= 10) return 5;
  return Math.min(60, 5 + (n - 10) * 5);
}

export function slotFailed(id: string, now = Date.now()): void {
  const h = health.get(id) ?? { fails: 0, until: 0, lastFailAt: 0 };
  h.fails++;
  h.lastFailAt = now;
  h.until = now + skipMinutes(h.fails) * 60_000;
  health.set(id, h);
}

export function slotSucceeded(id: string): void {
  health.delete(id);
}

export function slotSkipped(id: string, now = Date.now()): boolean {
  const h = health.get(id);
  return h !== undefined && h.until > now;
}

export function slotHealth(id: string): { fails: number; skip_until: number; last_fail_at: number } {
  const h = health.get(id);
  return { fails: h?.fails ?? 0, skip_until: h && h.until > Date.now() ? h.until : 0, last_fail_at: h?.lastFailAt ?? 0 };
}

/** 登録を変えた・キーを入れ直したとき（その API はすぐにまた使ってみる） */
export function resetSlotHealth(id?: string): void {
  if (id === undefined) health.clear();
  else health.delete(id);
}
