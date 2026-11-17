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
  /** クレーンゲームのお客さん（台の調整ができる） */
  crane?: boolean;
  /** ネタ枠（まれに出る） */
  rare?: boolean;
}

export const STAGES = ["konbini", "arcade"] as const;
export type StageId = (typeof STAGES)[number];

export function isStage(v: unknown): v is StageId {
  return typeof v === "string" && (STAGES as readonly string[]).includes(v);
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
  cache.set(lang, raw.stages);
  return raw.stages;
}

export function allCustomers(stage: StageId, lang: Lang = "ja"): Customer[] {
  const stages = load(lang);
  return stages[stage] ?? stages["konbini"] ?? [];
}

export function randomCustomer(stage: StageId, avoidTitles: string[] = [], lang: Lang = "ja"): Customer {
  const list = allCustomers(stage, lang);
  const fresh = list.filter((c) => !avoidTitles.includes(c.title));
  const pool = fresh.length > 0 ? fresh : list;
  // ネタ枠（rare）は出にくくする（重み 0.25）
  const weights = pool.map((c) => (c.rare ? 0.25 : 1));
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
    rare: c.rare === true,
  };
}
