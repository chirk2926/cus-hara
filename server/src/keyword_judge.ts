// キーワードによる採点。AIが使えないとき・失敗したときに使う。
// 判定に使う語は data/judge_words.json（Godot 側の scripts/offline_judge.gd と共通）。
// 点数の規則は docs/SPEC.md 5.1節。規則を変えるときは offline_judge.gd も同じように直すこと。
import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import type { Customer } from "./scenarios.ts";
import type { Lang } from "./lang.ts";

export interface Judgement {
  anger_delta: number;
  resolve_delta: number;
  yielded: boolean;
  customer_reply: string;
  comment: string;
}

export interface CustomerLineJudgement {
  anger_delta: number;
  resolve_delta: number;
  comment: string;
}

interface Words {
  apology: string[];
  empathy: string[];
  listen: string[];
  firm: string[];
  polite: string[];
  rude: string[];
  excuse: string[];
  negation: string[];
  apology_forms: string[];
  abuse: string[];
  pressure: string[];
  generic_lines: Record<string, string | string[]>;
  polite_pattern: string;
}

// 店長の一言など、判定が出す文言
const COMMENTS: Record<Lang, Record<string, string>> = {
  ja: {
    solution: "具体的な解決策、いいね！",
    cushion: "断る時こそクッション言葉を。",
    firm: "毅然とした対応、その調子。",
    only_sorry: "謝るだけじゃ解決しないぞ。",
    excuse: "言い訳に聞こえてるぞ。",
    casual: "タメ口は火に油だ。",
    short: "短すぎる。ちゃんと話そう。",
    repeat: "同じ返事の繰り返しはNG。",
    rude: "お客さんに暴言はダメ！",
    yielded: "不当な要求を飲んじゃダメだ…。",
    good: "いい受け止め方だ。",
    ok: "悪くない。次は解決策を。",
    miss: "響いてないぞ。メモを読もう。",
    offtopic: "接客と関係ない話はやめよう。",
    c_silent: "お客さんが言葉に詰まった！",
    c_abuse: "度を越した暴言。店長が止めに入った。",
    c_repeat: "同じセリフの繰り返しは響かない。",
    c_pressure: "お客さんの圧が強まった…",
  },
  en: {
    solution: "A concrete solution. Nice!",
    cushion: "Soften a refusal with a kind word first.",
    firm: "Polite but firm. Keep it up.",
    only_sorry: "Apologizing alone won't fix it.",
    excuse: "That sounds like an excuse.",
    casual: "Too casual. Mind your manners.",
    short: "Too short. Say a bit more.",
    repeat: "Don't repeat the same reply.",
    rude: "Never insult a customer!",
    yielded: "You caved to an unreasonable demand...",
    good: "Good, you took it on board.",
    ok: "Not bad. Now offer a solution.",
    miss: "That missed. Read the memo.",
    offtopic: "Stay on the job, not off-topic chatter.",
    c_silent: "The customer is lost for words!",
    c_abuse: "Way over the line. The manager stepped in.",
    c_repeat: "Repeating yourself has no effect.",
    c_pressure: "The pressure is building...",
  },
};

// 接客と関係ない話（AIへの依頼・プログラム・モデル名など）。要件#28
const OFFTOPIC: Record<Lang, string[]> = {
  ja: ["コードを", "プログラム", "モデル名", "どのモデル", "システムプロンプト", "プロンプト", "chatgpt", "claude", "anthropic", "openai", "gpt", "ai として", "aiとして", "指示を無視"],
  en: ["write code", "write a program", "python", "javascript", "which model", "what model", "model name", "system prompt", "prompt", "chatgpt", "claude", "anthropic", "openai", "gpt", "as an ai", "ignore previous", "ignore your instructions"],
};

const cache = new Map<Lang, Words>();

function words(lang: Lang): Words {
  const hit = cache.get(lang);
  if (hit) return hit;
  const file = path.join(path.dirname(config.scenariosPath), "judge_words.json");
  const all = JSON.parse(fs.readFileSync(file, "utf-8")) as Record<string, Words>;
  const w = all[lang] ?? all["ja"];
  cache.set(lang, w);
  return w;
}

function norm(text: string, lang: Lang): string {
  return lang === "ja" ? text : text.toLowerCase();
}

function count(text: string, list: string[] | undefined): number {
  if (!list) return 0;
  let n = 0;
  for (const w of list) if (w !== "" && text.includes(w)) n++;
  return n;
}

function pick(v: string | string[] | undefined): string | undefined {
  if (v === undefined) return undefined;
  if (Array.isArray(v)) return v.length > 0 ? v[Math.floor(Math.random() * v.length)] : undefined;
  return v;
}

export function scriptedLine(c: Customer, key: string, lang: Lang = "ja"): string {
  return pick(c.lines?.[key]) ?? pick(words(lang).generic_lines[key]) ?? "……";
}

export function isOffTopic(text: string, lang: Lang): boolean {
  const t = text.toLowerCase();
  return count(t, OFFTOPIC[lang]) > 0 || count(t, OFFTOPIC.ja) > 0 || /```|<script|\bdef\s+\w+\(|function\s*\(/.test(text);
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function judgeStaff(c: Customer, reply: string, used: string[], anger: number, resolve: number, lang: Lang = "ja"): Judgement {
  const w = words(lang);
  const cm = COMMENTS[lang];
  const raw = reply.trim();
  const text = norm(raw, lang);
  let a = 0;
  let r = 0;
  let comment = "";
  let yielded = false;

  const apology = count(text, w.apology);
  const empathy = count(text, w.empathy);
  const listen = count(text, w.listen);
  const firm = count(text, w.firm);
  const polite = count(text, w.polite);
  const rude = count(text, w.rude);
  const excuse = count(text, w.excuse);
  const solution = Math.min(count(text, (c.solution_keywords ?? []).map((k) => norm(k, lang))), 2);
  let stripped = text;
  for (const f of w.apology_forms) if (f !== "") stripped = stripped.split(f).join("");
  const negated = count(stripped, w.negation) > 0;
  if (count(text, (c.yield_keywords ?? []).map((k) => norm(k, lang))) > 0 && !negated) yielded = true;

  if (apology > 0) a -= 8;
  if (empathy > 0) a -= 7;
  if (listen > 0) { a -= 5; r += 8; }
  if (polite > 0) a -= 3;
  if (solution > 0) { a -= 6 * solution; r += 24 * solution; comment = cm.solution; }
  if (firm > 0) {
    r += 15;
    if (apology === 0 && empathy === 0) { a += 6; comment = cm.cushion; }
    else if (comment === "") comment = cm.firm;
  }
  if (apology > 0 && empathy === 0 && listen === 0 && solution === 0 && firm === 0 && used.length >= 2) {
    a = -2;
    comment = cm.only_sorry;
  }
  if (excuse > 0) { a += 8; comment = cm.excuse; }
  if (!new RegExp(w.polite_pattern).test(text)) { a += 8; comment = cm.casual; }
  const tooShort = lang === "ja" ? raw.length < 6 : raw.split(/\s+/).filter(Boolean).length < 3;
  if (tooShort) { a += 10; comment = cm.short; }
  if (used.includes(raw)) { a = Math.max(a, 0) + 12; r = 0; comment = cm.repeat; }
  if (isOffTopic(raw, lang)) { a = Math.max(a, 0) + 12; r = 0; yielded = false; comment = cm.offtopic; }
  if (rude > 0) { a += 25; r = 0; comment = cm.rude; }
  if (yielded) comment = cm.yielded;
  if (comment === "") comment = a < -8 ? cm.good : a < 0 ? cm.ok : cm.miss;

  a = clamp(a, -30, 30);
  r = clamp(r, 0, 45);
  const na = anger + a;
  const nr = resolve + r;
  let key = "neutral";
  if (yielded) key = "yielded";
  else if (na >= 100) key = "explode";
  else if (nr >= 100) key = "resolved";
  else if (a >= 5) key = "angry";
  else if (a <= -6) key = nr < 60 && Math.random() < 0.4 ? "demand" : "calm";
  return { anger_delta: Math.round(a), resolve_delta: Math.round(r), yielded, customer_reply: scriptedLine(c, key, lang), comment };
}

/** 対戦: 客役プレイヤーのセリフの評価 */
export function judgeCustomerLine(c: Customer, line: string, used: string[], lang: Lang = "ja"): CustomerLineJudgement {
  const w = words(lang);
  const cm = COMMENTS[lang];
  const raw = line.trim();
  const text = norm(raw, lang);
  if (raw === "") return { anger_delta: 0, resolve_delta: 12, comment: cm.c_silent };
  if (count(text, w.abuse) > 0) return { anger_delta: 0, resolve_delta: 15, comment: cm.c_abuse };
  if (used.includes(raw)) return { anger_delta: 0, resolve_delta: 8, comment: cm.c_repeat };
  if (isOffTopic(raw, lang)) return { anger_delta: 0, resolve_delta: 8, comment: cm.offtopic };
  let p = 3;
  const len = lang === "ja" ? raw.length : raw.length / 2;
  if (len >= 12) p += 2;
  if (len >= 30) p += 2;
  if (raw.includes("！") || raw.includes("!")) p += 1;
  if (count(text, (c.yield_keywords ?? []).map((k) => norm(k, lang))) > 0) p += 2;
  p += Math.min(count(text, w.pressure), 2) * 1.5;
  return { anger_delta: Math.round(clamp(p, 0, 12)), resolve_delta: 0, comment: cm.c_pressure };
}
