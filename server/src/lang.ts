// 対応言語。増やすときは data/scenarios.<lang>.json と data/judge_words.json の <lang> と、
// keyword_judge.ts / llm.ts の文言を足す（docs/MAINTENANCE.md「言語を増やす」）。
export const LANGS = ["ja", "en"] as const;
export type Lang = (typeof LANGS)[number];

export function toLang(v: unknown): Lang {
  return typeof v === "string" && (LANGS as readonly string[]).includes(v) ? (v as Lang) : "ja";
}
