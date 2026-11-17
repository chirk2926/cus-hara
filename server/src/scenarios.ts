// 台本のお客さんデータ（data/scenarios.json。Godot 側と同じファイル）
import fs from "node:fs";
import { config } from "./config.ts";

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
}

export const STAGES = ["konbini", "arcade"] as const;
export type StageId = (typeof STAGES)[number];

export function isStage(v: unknown): v is StageId {
  return typeof v === "string" && (STAGES as readonly string[]).includes(v);
}

let cache: Record<string, Customer[]> | null = null;

export function allCustomers(stage: StageId): Customer[] {
  if (cache === null) {
    const raw = JSON.parse(fs.readFileSync(config.scenariosPath, "utf-8")) as { stages: Record<string, Customer[]> };
    cache = raw.stages;
  }
  return cache[stage] ?? cache["konbini"] ?? [];
}

export function randomCustomer(stage: StageId, avoidTitles: string[] = []): Customer {
  const list = allCustomers(stage);
  const fresh = list.filter((c) => !avoidTitles.includes(c.title));
  const pool = fresh.length > 0 ? fresh : list;
  return structuredClone(pool[Math.floor(Math.random() * pool.length)]);
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
  };
}
