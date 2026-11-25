// AI の指示文（システムプロンプト）を管理画面から変えられるようにする（要件#130）。
// モード: "system" = プログラムに入っている指示文（既定）/ "custom" = 管理画面で書いた指示文（空の欄は既定のまま）。
// 出力の形（JSON のスキーマ）はプログラムが決めるので、指示文を変えても答えの形はくずれない。変わるのは中身の質だけ。
// 保存先は DB の settings 表（"aiPrompts"）。API キーなどの秘密の値は入らない。
import { storedSettings, storeSetting } from "./db.ts";

export type PromptKey = "generate" | "judge" | "vs_customer" | "moderation" | "translate";
export const PROMPT_KEYS: PromptKey[] = ["generate", "judge", "vs_customer", "moderation", "translate"];
export const PROMPT_LABELS: Record<PromptKey, string> = {
  generate: "お客さんづくり（1人用・対戦のお客さんの設定）",
  judge: "1人用・対戦の店員の返事の採点",
  vs_customer: "対戦の客役のセリフの採点",
  moderation: "不適切な発言のチェック（対戦）",
  translate: "グローバルサーバーの翻訳（対戦）",
};
const MAX_LEN = 20000;
const KEY = "aiPrompts";

const defaults = new Map<PromptKey, string>();
let mode: "system" | "custom" = "system";
let custom: Partial<Record<PromptKey, string>> = {};
let loaded = false;

/** プログラムの指示文を登録する（llm.ts が起動時に呼ぶ） */
export function registerDefaultPrompt(k: PromptKey, text: string): void {
  defaults.set(k, text);
}

function load(): void {
  if (loaded) return;
  loaded = true;
  try {
    const raw = storedSettings()[KEY];
    if (raw === undefined) return;
    const o = JSON.parse(raw) as { mode?: string; texts?: Record<string, unknown> };
    mode = o.mode === "custom" ? "custom" : "system";
    custom = {};
    for (const k of PROMPT_KEYS) {
      const t = o.texts?.[k];
      if (typeof t === "string" && t.trim() !== "") custom[k] = t.slice(0, MAX_LEN);
    }
  } catch {
    // DB がまだ開いていない（テスト）・壊れた値は既定のまま
  }
}

/** 起動のとき・設定を読み直すとき */
export function reloadPrompts(): void {
  loaded = false;
  load();
}

/** AI に渡す指示文。管理画面のモードで、書いた指示文があればそれを使う */
export function prompt(k: PromptKey): string {
  load();
  const c = mode === "custom" ? custom[k] : undefined;
  return c ?? defaults.get(k) ?? "";
}

export function promptsForAdmin() {
  load();
  return {
    mode,
    items: PROMPT_KEYS.filter((k) => defaults.has(k)).map((k) => ({ key: k, label: PROMPT_LABELS[k], default: defaults.get(k) ?? "", custom: custom[k] ?? "", in_use: mode === "custom" && custom[k] !== undefined ? "custom" : "system" })),
  };
}

/** 保存する。texts の空の欄は「既定のまま」。戻り値は記録用の短い説明 */
export function savePrompts(body: { mode?: unknown; texts?: unknown }): string {
  load();
  const m = body.mode === "custom" ? "custom" : "system";
  const next: Partial<Record<PromptKey, string>> = {};
  const texts = (body.texts ?? {}) as Record<string, unknown>;
  for (const k of PROMPT_KEYS) {
    const t = texts[k];
    if (typeof t !== "string") {
      if (custom[k] !== undefined) next[k] = custom[k];
      continue;
    }
    const v = t.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").slice(0, MAX_LEN);
    if (v.trim() !== "") next[k] = v;
  }
  mode = m;
  custom = next;
  storeSetting(KEY, JSON.stringify({ mode, texts: custom }));
  const changed = PROMPT_KEYS.filter((k) => custom[k] !== undefined).map((k) => PROMPT_LABELS[k]);
  return `モード: ${mode === "custom" ? "管理画面の指示文" : "プログラムの指示文"}／書きかえた指示文: ${changed.length ? changed.join("、") : "なし"}`;
}
