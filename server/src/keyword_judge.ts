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
  /** AI が採点と一緒に見た「不適切な発言」の判定（対戦だけで使う。要件#93）。AI を使わないときはない */
  flag?: "sexual" | "hate" | "threat" | "personal_info" | "none";
}

export interface CustomerLineJudgement {
  anger_delta: number;
  resolve_delta: number;
  comment: string;
  flag?: "sexual" | "hate" | "threat" | "personal_info" | "none";
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
  excuse_soft?: string[];
  excuse_exempt?: string[];
  stop_tokens?: string[];
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
    specific: "メモの中身に触れているのはいい。あと一歩、具体的に。",
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
    specific: "Good, you're using what's in the memo. Now be more specific.",
    offtopic: "Stay on the job, not off-topic chatter.",
    c_silent: "The customer is lost for words!",
    c_abuse: "Way over the line. The manager stepped in.",
    c_repeat: "Repeating yourself has no effect.",
    c_pressure: "The pressure is building...",
  },
  zh: {
    solution: "具体的解决方案，很好！",
    cushion: "拒绝的时候更要先说句软话。",
    firm: "坚定又得体，保持住。",
    only_sorry: "光道歉解决不了问题。",
    excuse: "听起来像在找借口。",
    casual: "说话太随便，火上浇油。",
    short: "太短了。好好说几句。",
    repeat: "重复同样的回答可不行。",
    rude: "不能对顾客恶语相向！",
    yielded: "不能答应无理要求啊…。",
    good: "接得很好。",
    ok: "还不错。接下来给出解决方案。",
    miss: "没说到点上。看看备忘录。",
    specific: "提到了备忘录里的内容，不错。再具体一点。",
    offtopic: "别聊和接待无关的话题。",
    c_silent: "顾客一时语塞！",
    c_abuse: "骂得太过分了。店长出面制止了。",
    c_repeat: "重复同样的台词没有效果。",
    c_pressure: "顾客的气势越来越强了…",
  },
};

// 接客と関係ない話（AIへの依頼・プログラム・モデル名など）。要件#28
const OFFTOPIC: Record<Lang, string[]> = {
  ja: ["コードを", "プログラム", "モデル名", "どのモデル", "システムプロンプト", "プロンプト", "chatgpt", "claude", "anthropic", "openai", "gpt", "ai として", "aiとして", "指示を無視"],
  en: ["write code", "write a program", "python", "javascript", "which model", "what model", "model name", "system prompt", "prompt", "chatgpt", "claude", "anthropic", "openai", "gpt", "as an ai", "ignore previous", "ignore your instructions"],
  zh: ["写代码", "写程序", "编程", "模型名", "哪个模型", "什么模型", "系统提示", "提示词", "忽略指令", "忽略之前", "作为ai", "chatgpt", "claude", "anthropic", "openai", "gpt"],
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

// ---------------------------------------------------------------- 精度を上げるための道具（要件#73。scripts/offline_judge.gd と同じ）

/** 文を節に分ける（「、」「。」や but で区切る）。否定が同じ節にあるかを見るため */
export function clauses(text: string, lang: Lang): string[] {
  const re = lang === "en" ? /[.,!?;\n]|\bbut\b/g : /[。、！？!?，,．\n]/g;
  return text.replace(re, "|").split("|").filter((x) => x !== "");
}

/** 中身のある語のかたまり: 日本語は漢字・カタカナ、中国語は漢字の2文字の並び、英語は4文字以上の単語 */
export function tokens(text: string, lang: Lang): Set<string> {
  const out = new Set<string>();
  if (lang === "en") {
    for (const m of text.toLowerCase().matchAll(/[a-z]{4,}/g)) out.add(m[0]);
    return out;
  }
  const re = lang === "zh" ? /[\u4E00-\u9FFF]{2,}/g : /[\u4E00-\u9FFF\u30A0-\u30FF]{2,}/g;
  for (const m of text.matchAll(re)) {
    const run = m[0];
    for (let i = 0; i < run.length - 1; i++) out.add(run.slice(i, i + 2));
  }
  return out;
}

/** 2つの文の似ている度合い（0〜1） */
export function similarity(a: string, b: string, lang: Lang): number {
  const grams = (t: string) => {
    const s = new Set<string>();
    if (lang === "en") for (const w of t.toLowerCase().split(" ").filter(Boolean)) s.add(w);
    else for (let i = 0; i < t.length - 1; i++) s.add(t.slice(i, i + 2));
    return s;
  };
  const ta = grams(a);
  const tb = grams(b);
  if (ta.size === 0 || tb.size === 0) return a === b ? 1 : 0;
  let inter = 0;
  for (const k of ta) if (tb.has(k)) inter++;
  return inter / (ta.size + tb.size - inter);
}

/** 返事が、メモの中身にいくつ触れているか */
export function memoOverlap(c: Customer, text: string, lang: Lang, stop: string[]): number {
  const mt = tokens(c.memo ?? "", lang);
  let n = 0;
  for (const k of tokens(text, lang)) if (mt.has(k) && !stop.includes(k)) n++;
  return n;
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
  let listen = count(text, w.listen);
  const firm = count(text, w.firm);
  const polite = count(text, w.polite);
  const rude = count(text, w.rude);
  const solution = Math.min(count(text, (c.solution_keywords ?? []).map((k) => norm(k, lang))), 2);
  // 言い訳: 「いつでも」などの「でも」は除く。「でも／but」は、解決策や断りが続くなら言い訳にしない（要件#73）
  let exText = text;
  for (const e of w.excuse_exempt ?? []) if (e !== "") exText = exText.split(norm(e, lang)).join("");
  let excuse = count(exText, w.excuse);
  if (solution === 0 && firm === 0) excuse += count(exText, w.excuse_soft);
  // 屈服: 不当な要求の語と否定が「同じ節」にあるかで見る
  let stripped = text;
  for (const f of w.apology_forms) if (f !== "") stripped = stripped.split(f).join("");
  const yk = (c.yield_keywords ?? []).map((k) => norm(k, lang));
  for (const cl of clauses(stripped, lang)) if (count(cl, yk) > 0 && count(cl, w.negation) === 0) yielded = true;
  // 同じ謝罪ばかりだと効きが落ちる
  const pastApology = used.filter((u) => count(norm(u, lang), w.apology) > 0).length;
  // ていねいに質問して聞き出すのも「話を聞く」に数える
  if (listen === 0 && /[？?]/.test(text) && polite > 0) listen = 1;
  const overlap = memoOverlap(c, text, lang, w.stop_tokens ?? []);

  if (apology > 0) a -= pastApology >= 2 ? 3 : 8;
  if (empathy > 0) a -= 7;
  if (listen > 0) { a -= 5; r += 8; }
  if (polite > 0) a -= 3;
  if (solution > 0) { a -= 6 * solution; r += 24 * solution; comment = cm.solution; }
  else if (overlap >= 2) { a -= 3; r += 10; comment = cm.specific; }
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
  // 英語は単語数、日本語・中国語は文字数で短さを見る
  const tooShort = lang === "en" ? raw.split(/\s+/).filter(Boolean).length < 3 : raw.length < 6;
  if (tooShort) { a += 10; comment = cm.short; }
  const nearRepeat = used.some((u) => similarity(raw, u, lang) >= 0.8);
  if (used.includes(raw) || nearRepeat) { a = Math.max(a, 0) + 12; r = 0; comment = cm.repeat; }
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
  const len = lang === "en" ? raw.length / 2 : raw.length;
  if (len >= 12) p += 2;
  if (len >= 30) p += 2;
  if (raw.includes("！") || raw.includes("!")) p += 1;
  if (count(text, (c.yield_keywords ?? []).map((k) => norm(k, lang))) > 0) p += 2;
  p += Math.min(count(text, w.pressure), 2) * 1.5;
  return { anger_delta: Math.round(clamp(p, 0, 12)), resolve_delta: 0, comment: cm.c_pressure };
}
