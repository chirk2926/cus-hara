// 店の行動ボタン（割引・土下座・メダル返還・補填、クレーン台の調整の結果）。要件#34, #37
// 効果は data/actions.json の表で決まる（AIには任せない。サーバーとゲームで結果をそろえるため）。
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import { type Customer, type StageId, machineOf } from "./scenarios.ts";
import type { Lang } from "./lang.ts";
import { scriptedLine, type Judgement } from "./keyword_judge.ts";

interface ActionTable {
  stages: Record<string, string[]>;
  /** ゲームセンターの台の種類ごとのボタン（要件#54） */
  machines: Record<string, string[]>;
  /** ミニゲームを開くボタン（結果は crane_won / crane_lost として送られる） */
  minigame: string[];
  /** 判定しないボタン（筐体のデータを見る） */
  info: string[];
  labels: Record<string, Record<string, string>>;
  effects: Record<string, { anger: number; resolve: number; yielded?: boolean; reply: string }>;
  comments: Record<string, Record<string, string>>;
  default: Record<string, string>;
  /** 台の問題（要件#99）があるお客さんだけに出す行動 */
  repair: string[];
  /** 1人用だけの行動（筐体の前へ行く・様子を見に行く）。対戦では出さない */
  solo_only: string[];
  /** 「ボタンが反応しない」がお客さんのうそになる確率 */
  lie_chance: number;
  /** 台の問題ごとの台の種類と、行動の効果 */
  problems: Record<string, { machine: string; actions: Record<string, string> }>;
}

let table: ActionTable | null = null;

export function actions(): ActionTable {
  if (table === null) {
    const file = path.join(path.dirname(config.scenariosPath), "actions.json");
    table = JSON.parse(fs.readFileSync(file, "utf-8")) as ActionTable;
  }
  return table;
}

export const CRANE_RESULTS = ["crane_won", "crane_lost"] as const;

/** そのステージ・そのお客さんで使える行動か */
export function isAllowed(stage: StageId, c: Customer, id: string, versus = false): boolean {
  const t = actions();
  if ((CRANE_RESULTS as readonly string[]).includes(id)) return stage === "arcade" && machineOf(c) === "crane";
  if (t.minigame.includes(id) || t.info.includes(id)) return false;
  // 台の問題の行動（要件#99）: そのお客さんの問題の表にあるものだけ。1人用だけの行動は対戦では使えない
  if (t.repair.includes(id)) {
    if (versus && t.solo_only.includes(id)) return false;
    const pr = c.problem ? t.problems[c.problem] : undefined;
    return stage === "arcade" && pr !== undefined && id in pr.actions;
  }
  if (stage === "arcade") return (t.machines[machineOf(c)] ?? []).includes(id);
  return (t.stages[stage] ?? []).includes(id);
}

export function actionLabel(id: string, lang: Lang): string {
  return actions().labels[lang]?.[id] ?? actions().labels.ja[id] ?? id;
}

/** 行動の効果の種類: good / neutral / bad / yield / crane_won / crane_lost */
export function effectKind(c: Customer, id: string): string {
  if ((CRANE_RESULTS as readonly string[]).includes(id)) return id;
  return c.actions?.[id] ?? actions().default[id] ?? "neutral";
}

/** 表どおりの判定（お客さんの返事は台本） */
export function judgeAction(c: Customer, id: string, anger: number, resolve: number, lang: Lang): Judgement {
  const kind = effectKind(c, id);
  const e = actions().effects[kind] ?? actions().effects.neutral;
  const yielded = e.yielded === true;
  let reply = e.reply;
  if (!yielded && anger + e.anger >= 100) reply = "explode";
  else if (!yielded && resolve + e.resolve >= 100) reply = "resolved";
  return {
    anger_delta: e.anger,
    resolve_delta: e.resolve,
    yielded,
    customer_reply: scriptedLine(c, reply, lang),
    comment: actions().comments[lang]?.[kind] ?? actions().comments.ja[kind] ?? "",
  };
}

/** AIに渡す、スタッフの行動の説明（会話の履歴に入れる） */
export function actionAsStaffLine(id: string, lang: Lang): string {
  if (lang === "zh") return `（行动：${actionLabel(id, "zh")}）`;
  if (lang === "ko") return `(행동: ${actionLabel(id, "ko")})`;
  return lang === "ja" ? `（行動: ${actionLabel(id, "ja")}）` : `(Action: ${actionLabel(id, "en")})`;
}

/**
 * 台の問題（要件#99）をお客さんに当てはめる。台の種類と行動の効果を表から入れる（AI には任せない）。
 * 「ボタンが反応しない」は lie_chance の確率でお客さんのうそ（button_lie）になる。
 */
export function applyProblem(c: Customer, rnd: () => number = Math.random): Customer {
  const t = actions();
  if (!c.problem || !(c.problem in t.problems)) {
    delete c.problem;
    return c;
  }
  if (c.problem === "button" && rnd() < t.lie_chance) c.problem = "button_lie";
  const pr = t.problems[c.problem];
  c.machine = pr.machine;
  c.crane = false;
  c.actions = { ...(c.actions ?? {}), ...pr.actions };
  return c;
}
