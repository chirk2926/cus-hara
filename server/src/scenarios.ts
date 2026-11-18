// 台本のお客さんデータ（data/scenarios.json。Godot 側と同じファイル）
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import type { Lang } from "./lang.ts";

export interface Look {
  body_color?: string;
  skin_color?: string;
  hair_color?: string;
  hair?: string;
  build?: string;
  accessory?: string;
  height?: number;
}

export interface Customer {
  title: string;
  name: string;
  look: Look;
  memo: string;
  opening: string;
  demand: string;
  patience: number;
  start_anger: number;
  solution_keywords?: string[];
  yield_keywords?: string[];
  lines?: Record<string, string | string[]>;
  /** 店の行動ボタンの効果（good / neutral / bad / yield）。data/actions.json */
  actions?: Record<string, string>;
  /** クレーンゲームのお客さん（台の調整ができる）。machine === "crane" から決まる */
  crane?: boolean;
  /** ゲームセンターの台の種類（要件#54）: crane / medal / rhythm / video / none。行動ボタンがこれで変わる */
  machine?: string;
  /** 「〇〇円使っても取れない」と言うクレーンのお客さん（要件#55, #57）。文中の {spent} を金額に置き換える */
  spend?: boolean;
  /** 筐体のデータ（spend のお客さんだけ。materializeSpend が入れる） */
  spend_data?: SpendData;
  /** ネタ枠（まれに出る） */
  rare?: boolean;
}

export const STAGES = ["konbini", "arcade"] as const;
export type StageId = (typeof STAGES)[number];

export function isStage(v: unknown): v is StageId {
  return typeof v === "string" && (STAGES as readonly string[]).includes(v);
}

export interface SpendData {
  /** お客さんが言っている金額（円） */
  claimed: number;
  /** 筐体の記録の金額（円） */
  actual: number;
  /** 1個あたりの目安 = 景品原価 / ペイアウト率 */
  expected: number;
  payout: number;
  /** 言っている金額が嘘か */
  lie: boolean;
}

/** クレーンゲームの景品原価（円・固定。要件#55） */
export const PRIZE_COST = 1100;
export const PAYOUT_DEFAULT = 30;
export const PAYOUT_MIN = 10;
export const PAYOUT_MAX = 80;

export function clampPayout(v: unknown): number {
  const n = Number(v);
  if (!Number.isFinite(n)) return PAYOUT_DEFAULT;
  return Math.min(PAYOUT_MAX, Math.max(PAYOUT_MIN, Math.round(n)));
}

/** 1個あたりの目安（円）= 景品原価 / ペイアウト率 */
export function costPerPrize(payout: number): number {
  return Math.floor(PRIZE_COST / (clampPayout(payout) / 100));
}

export function machineOf(c: Customer): string {
  return c.machine ?? (c.crane ? "crane" : "none");
}

function yen(n: number, lang: Lang): string {
  const s = n.toLocaleString("en-US");
  return lang === "ja" ? `${s}円` : `${s} yen`;
}

function roundTo(n: number, step: number): number {
  return Math.max(step, Math.round(n / step) * step);
}

/**
 * 「〇〇円使っても取れない」のお客さんに金額を決める（要件#55, #57）。
 * 言う金額は、ペイアウト率から決まる1個あたりの目安の 0.6〜1.3 倍（ペイアウト率が低いほど大きな金額を言う）。
 * 4割は嘘（記録は言った額の 15〜45%）。本当なら記録は言った額の 90〜100%。
 * 嘘のときは「クレジットを補填」が屈服になり、記録を示して話すのが正解になる。
 */
export function materializeSpend(c: Customer, payout: number, lang: Lang, rnd: () => number = Math.random): Customer {
  if (!c.spend) return c;
  const p = clampPayout(payout);
  const expected = costPerPrize(p);
  const claimed = Math.max(1000, roundTo(expected * (0.6 + 0.7 * rnd()), 500));
  const lie = rnd() < 0.4;
  const actual = lie ? roundTo(claimed * (0.15 + 0.3 * rnd()), 100) : roundTo(claimed * (0.9 + 0.1 * rnd()), 100);
  const text = yen(claimed, lang);
  const sub = (v: string) => v.split("{spent}").join(text);
  c.title = sub(c.title);
  c.memo = sub(c.memo);
  c.opening = sub(c.opening);
  c.demand = sub(c.demand);
  if (c.lines) {
    for (const [k, v] of Object.entries(c.lines)) c.lines[k] = Array.isArray(v) ? v.map(sub) : sub(v);
  }
  c.spend_data = { claimed, actual, expected, payout: p, lie };
  c.actions = { ...(c.actions ?? {}) };
  if (lie) {
    c.actions.credit = "yield";
    const extra = lang === "ja" ? ["記録", "データ", "履歴", "実際"] : ["record", "data", "log", "actually"];
    c.solution_keywords = [...(c.solution_keywords ?? []), ...extra];
  }
  return c;
}

/** 筐体のデータを AI に伝える文（採点の材料） */
export function spendFacts(c: Customer, lang: Lang): string {
  const d = c.spend_data;
  if (!d) return "";
  return lang === "ja"
    ? `筐体の記録: このお客さんの投入額は実際には ${d.actual}円（本人の主張は ${d.claimed}円）。1個あたりの目安は ${d.expected}円（ペイアウト率 ${d.payout}%）。${d.lie ? "主張は誇張・嘘。スタッフが記録をもとに冷静に事実を伝えたら、お客さんは言い返せなくなる（納得度を上げる）。" : "主張はほぼ本当。目安に近いので、景品を取りやすい位置に直すなどの対応が正解。"}`
    : `Machine log: this customer actually put in ${d.actual} yen (they claim ${d.claimed} yen). Expected cost per prize is ${d.expected} yen (payout ${d.payout}%). ${d.lie ? "The claim is exaggerated. If staff calmly cite the record, the customer can't argue (raise resolve)." : "The claim is basically true and near the payout mark, so moving the prize somewhere easier is the right call."}`;
}

const cache = new Map<Lang, Record<string, Customer[]>>();

/** 言語ごとの台本ファイル: 日本語は scenarios.json、それ以外は scenarios.<lang>.json（無ければ日本語） */
function load(lang: Lang): Record<string, Customer[]> {
  const hit = cache.get(lang);
  if (hit) return hit;
  let file = config.scenariosPath;
  if (lang !== "ja") {
    const alt = path.join(path.dirname(file), `scenarios.${lang}.json`);
    if (fs.existsSync(alt)) file = alt;
  }
  const raw = JSON.parse(fs.readFileSync(file, "utf-8")) as { stages: Record<string, Customer[]> };
  for (const list of Object.values(raw.stages)) for (const c of list) if (c.machine) c.crane = c.machine === "crane";
  cache.set(lang, raw.stages);
  return raw.stages;
}

export function allCustomers(stage: StageId, lang: Lang = "ja"): Customer[] {
  const stages = load(lang);
  return stages[stage] ?? stages["konbini"] ?? [];
}

export function randomCustomer(stage: StageId, avoidTitles: string[] = [], lang: Lang = "ja", wildOnly = false, payout = PAYOUT_DEFAULT): Customer {
  return materializeSpend(pickCustomer(stage, avoidTitles, lang, wildOnly, payout), payout, lang);
}

/** 「取れない」クレームの出やすさ（要件#55）: ペイアウト率 30% で 1 倍。低いほど出やすく、高いほど出にくい */
export function spendWeight(payout: number): number {
  return PAYOUT_DEFAULT / clampPayout(payout);
}

function pickCustomer(stage: StageId, avoidTitles: string[], lang: Lang, wildOnly: boolean, payout: number): Customer {
  const all = allCustomers(stage, lang);
  // 「要注意人物」イベント（要件#52）: ネタ枠（rare）だけから選ぶ
  const rares = all.filter((c) => c.rare);
  const list = wildOnly && rares.length > 0 ? rares : all;
  const fresh = list.filter((c) => !avoidTitles.includes(c.title));
  const pool = fresh.length > 0 ? fresh : list;
  // ネタ枠（rare）は出にくくする（重み 0.25）
  const weights = pool.map((c) => (c.rare && !wildOnly ? 0.25 : 1) * (c.spend && stage === "arcade" ? spendWeight(payout) : 1));
  let r = Math.random() * weights.reduce((a, b) => a + b, 0);
  for (let i = 0; i < pool.length; i++) {
    r -= weights[i];
    if (r <= 0) return structuredClone(pool[i]);
  }
  return structuredClone(pool[pool.length - 1]);
}

/** クライアントに見せてよい項目だけにする（採点用のキーワードは渡さない） */
export function publicCustomer(c: Customer) {
  return {
    title: c.title,
    name: c.name,
    look: c.look,
    memo: c.memo,
    opening: c.opening,
    demand: c.demand,
    patience: c.patience,
    start_anger: c.start_anger,
    crane: c.crane === true,
    machine: machineOf(c),
    rare: c.rare === true,
    // 筐体のデータ（「筐体のデータを見る」で見せる。要件#57）
    spend: c.spend_data ? { claimed: c.spend_data.claimed, actual: c.spend_data.actual, expected: c.spend_data.expected, payout: c.spend_data.payout } : null,
  };
}
