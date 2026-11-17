// レーティング（Elo方式）とランク名。数値は docs/SPEC.md の 6.4節。
export const RATING_START = 1000;
export const RATING_K = 32;

export const RANKS: Array<[number, string]> = [
  [1700, "伝説のクレーム処理班"],
  [1500, "エリアマネージャー"],
  [1350, "店長"],
  [1200, "副店長"],
  [1050, "バイトリーダー"],
  [900, "アルバイト"],
  [-Infinity, "研修生"],
];

export function rankName(rating: number): string {
  for (const [min, name] of RANKS) if (rating >= min) return name;
  return "研修生";
}

/** score: 勝ち=1 / 引き分け=0.5 / 負け=0 */
export function eloDelta(mine: number, theirs: number, score: number): number {
  const expected = 1 / (1 + Math.pow(10, (theirs - mine) / 400));
  return Math.round(RATING_K * (score - expected));
}
