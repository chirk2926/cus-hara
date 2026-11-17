// 店の行動ボタン（割引・土下座・メダル返還・補填、クレーン台の調整の結果）。要件#34, #37
// 効果は data/actions.json の表で決まる（AIには任せない。サーバーとゲームで結果をそろえるため）。
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import type { Customer, StageId } from "./scenarios.ts";
import type { Lang } from "./lang.ts";
import { scriptedLine, type Judgement } from "./keyword_judge.ts";

interface ActionTable {
  stages: Record<string, string[]>;
  labels: Record<string, Record<string, string>>;
  effects: Record<string, { anger: number; resolve: number; yielded?: boolean; reply: string }>;
  comments: Record<string, Record<string, string>>;
  default: Record<string, string>;
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
export function isAllowed(stage: StageId, c: Customer, id: string): boolean {
  if ((CRANE_RESULTS as readonly string[]).includes(id)) return stage === "arcade" && c.crane === true;
  return (actions().stages[stage] ?? []).includes(id);
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
  return lang === "ja" ? `（行動: ${actionLabel(id, "ja")}）` : `(Action: ${actionLabel(id, "en")})`;
}
