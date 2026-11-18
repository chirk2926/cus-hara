// 対応言語。増やすときは data/scenarios.<lang>.json と data/judge_words.json の <lang> と、
// keyword_judge.ts / llm.ts の文言を足す（docs/MAINTENANCE.md「言語を増やす」）。
export const LANGS = ["ja", "en", "zh"] as const;
export type Lang = (typeof LANGS)[number];

export function toLang(v: unknown): Lang {
  return typeof v === "string" && (LANGS as readonly string[]).includes(v) ? (v as Lang) : "ja";
}

/** 言語ごとの文を選ぶ（zh が無ければ英語） */
export function pick(lang: Lang, t: { ja: string; en: string; zh?: string }): string {
  if (lang === "zh") return t.zh ?? t.en;
  return lang === "ja" ? t.ja : t.en;
}

/** 言語ごとのお金の表記（要件#71）。中身はすべて円。1プレイ = 100円 = $1 = 8元 */
export function money(yen: number, lang: Lang): string {
  const fmt = (v: number) => {
    const whole = Math.floor(v + 1e-9);
    const cents = Math.round((v - whole) * 100);
    const s = whole.toLocaleString("en-US");
    return cents > 0 ? `${s}.${String(cents).padStart(2, "0")}` : s;
  };
  if (lang === "en") return `$${fmt(yen / 100)}`;
  if (lang === "zh") return `${fmt(yen * 0.08)}元`;
  return `${fmt(yen)}円`;
}

