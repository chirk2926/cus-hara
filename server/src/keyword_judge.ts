// キーワードによる採点。AIが使えないとき・失敗したときに使う。
// Godot 側の scripts/offline_judge.gd と同じ規則（docs/SPEC.md 5.1節）。両方を同時に直すこと。
import type { Customer } from "./scenarios.ts";

export interface Judgement {
  anger_delta: number;
  resolve_delta: number;
  yielded: boolean;
  customer_reply: string;
  comment: string;
}

const APOLOGY = ["申し訳", "すみません", "すいません", "失礼いたしました", "失礼しました", "お詫び", "ごめんなさい"];
const EMPATHY = ["お気持ち", "ご不便", "ご迷惑", "ご不快", "お察し", "おっしゃる通り", "おっしゃるとおり", "ごもっとも", "お怒り", "ご心配"];
const LISTEN = ["お聞かせ", "詳しく", "確認いたし", "確認させ", "お伺い", "状況を", "教えていただ"];
const FIRM = ["いたしかねます", "できかねます", "お受けできません", "応じかねます", "お断り", "致しかねます", "出来かねます", "お応えできません"];
const POLITE = ["ございます", "いたします", "でしょうか", "くださいませ", "恐れ入ります", "おります", "いただけます"];
const RUDE = ["うるさい", "うるせ", "黙れ", "だまれ", "帰れ", "バカ", "ばか", "馬鹿", "アホ", "あほ", "知らん", "知らねえ", "うざ", "クレーマー", "ふざけ", "めんどくさ", "はぁ？", "は？"];
const EXCUSE = ["でも", "だって", "仕方ない", "しょうがない", "ルールなので", "決まりなので", "私のせいじゃ", "私は悪く"];
const NEGATION = ["かねます", "できません", "出来ません", "お断り", "いたしません", "しません", "ません", "無理", "できない", "出来ない", "応じられ"];
const APOLOGY_FORMS = ["申し訳ございません", "申し訳ありません", "すみません", "すいません"];
const ABUSE = ["死ね", "しね", "殺す", "殺し", "ころす", "クズ", "ゴミ", "消えろ", "ぶっ殺"];
const PRESSURE = ["責任者", "店長", "誠意", "客だ", "どうしてくれ", "納得", "おかしい", "ありえない", "本部", "二度と", "時間を返", "常連"];

const GENERIC: Record<string, string | string[]> = {
  calm: ["……まあ、話は聞いてやる。", "ふん。少しは分かってるじゃないか。", "それで？どうしてくれるんだ？"],
  angry: ["なんだその態度は！", "こっちは客だぞ！！", "話にならん！責任者を出せ！"],
  neutral: ["で？それがどうした。", "だから何なんだって聞いてるんだ。"],
  demand: ["いいから誠意を見せろ、誠意を！", "タダにすれば済む話だろうが！"],
  resolved: "……分かった。今回はそれでいい。次は気をつけろよ。",
  explode: "もういい！！話にならん！店長を呼べ！！！",
  yielded: "最初からそうすればいいんだよ。また来るからな。",
};

function count(text: string, words: string[] | undefined): number {
  if (!words) return 0;
  let n = 0;
  for (const w of words) if (text.includes(w)) n++;
  return n;
}

function pick(v: string | string[] | undefined): string | undefined {
  if (v === undefined) return undefined;
  if (Array.isArray(v)) return v.length > 0 ? v[Math.floor(Math.random() * v.length)] : undefined;
  return v;
}

export function scriptedLine(c: Customer, key: string): string {
  return pick(c.lines?.[key]) ?? pick(GENERIC[key]) ?? "……";
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function judgeStaff(c: Customer, reply: string, used: string[], anger: number, resolve: number): Judgement {
  const text = reply.trim();
  let a = 0;
  let r = 0;
  let comment = "";
  let yielded = false;

  const apology = count(text, APOLOGY);
  const empathy = count(text, EMPATHY);
  const listen = count(text, LISTEN);
  const firm = count(text, FIRM);
  const polite = count(text, POLITE);
  const rude = count(text, RUDE);
  const excuse = count(text, EXCUSE);
  const solution = Math.min(count(text, c.solution_keywords), 2);
  let stripped = text;
  for (const f of APOLOGY_FORMS) stripped = stripped.split(f).join("");
  const negated = count(stripped, NEGATION) > 0;
  if (count(text, c.yield_keywords) > 0 && !negated) yielded = true;

  if (apology > 0) a -= 8;
  if (empathy > 0) a -= 7;
  if (listen > 0) { a -= 5; r += 8; }
  if (polite > 0) a -= 3;
  if (solution > 0) { a -= 6 * solution; r += 24 * solution; comment = "具体的な解決策、いいね！"; }
  if (firm > 0) {
    r += 15;
    if (apology === 0 && empathy === 0) { a += 6; comment = "断る時こそクッション言葉を。"; }
    else if (comment === "") comment = "毅然とした対応、その調子。";
  }
  if (apology > 0 && empathy === 0 && listen === 0 && solution === 0 && firm === 0 && used.length >= 2) {
    a = -2;
    comment = "謝るだけじゃ解決しないぞ。";
  }
  if (excuse > 0) { a += 8; comment = "言い訳に聞こえてるぞ。"; }
  const desu = /です|ます|ません|ございま/.test(text);
  if (!desu) { a += 8; comment = "タメ口は火に油だ。"; }
  if (text.length < 6) { a += 10; comment = "短すぎる。ちゃんと話そう。"; }
  if (used.includes(text)) { a = Math.max(a, 0) + 12; r = 0; comment = "同じ返事の繰り返しはNG。"; }
  if (rude > 0) { a += 25; r = 0; comment = "お客さんに暴言はダメ！"; }
  if (yielded) comment = "不当な要求を飲んじゃダメだ…。";
  if (comment === "") comment = a < -8 ? "いい受け止め方だ。" : a < 0 ? "悪くない。次は解決策を。" : "響いてないぞ。メモを読もう。";

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
  return { anger_delta: Math.round(a), resolve_delta: Math.round(r), yielded, customer_reply: scriptedLine(c, key), comment };
}

export interface CustomerLineJudgement {
  anger_delta: number;
  resolve_delta: number;
  comment: string;
}

/** 対戦: 客役プレイヤーのセリフの評価 */
export function judgeCustomerLine(c: Customer, line: string, used: string[]): CustomerLineJudgement {
  const text = line.trim();
  if (text === "") return { anger_delta: 0, resolve_delta: 12, comment: "お客さんが言葉に詰まった！" };
  if (count(text, ABUSE) > 0) return { anger_delta: 0, resolve_delta: 15, comment: "度を越した暴言。店長が止めに入った。" };
  if (used.includes(text)) return { anger_delta: 0, resolve_delta: 8, comment: "同じセリフの繰り返しは響かない。" };
  let p = 3;
  if (text.length >= 12) p += 2;
  if (text.length >= 30) p += 2;
  if (text.includes("！") || text.includes("!")) p += 1;
  if (count(text, c.yield_keywords) > 0) p += 2;
  p += Math.min(count(text, PRESSURE), 2) * 1.5;
  return { anger_delta: Math.round(clamp(p, 0, 12)), resolve_delta: 0, comment: "お客さんの圧が強まった…" };
}
