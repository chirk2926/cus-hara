// 対戦の不適切な発言の検出（要件#88）。
// 性的・アダルトな内容、差別、脅迫、個人情報（電話番号・住所など）を見つけたら、
// その発言は相手に見せず（伏せ字）、言った人に警告する。3回で負け（match.ts）。
// まずキーワードで見て、AI が使えるときは AI にも確かめさせる（AI が使えないときはキーワードだけ）。

import fs from "node:fs";
import path from "node:path";
import { config } from "./config.ts";
import { llmEnabled, moderateWithLlm } from "./llm.ts";
import { allow } from "./ratelimit.ts";
import { log } from "./log.ts";

export type ModerationCategory = "sexual" | "hate" | "threat" | "personal_info" | "none";

export interface ModerationResult {
  flagged: boolean;
  category: ModerationCategory;
  by: "keyword" | "ai" | "none";
}

/** 性的・アダルトな言葉と、差別・ひどい侮辱（data/moderation_words.json。ゲーム側の scripts/moderation.gd と共通。要件#94） */
const WORDS = JSON.parse(fs.readFileSync(path.join(path.dirname(config.scenariosPath), "moderation_words.json"), "utf-8")) as { sexual: string[]; hate: string[] };
const SEXUAL: string[] = WORDS.sexual;
const HATE: string[] = WORDS.hate;
/** 個人情報らしいもの（電話番号・メールアドレス）。金額（「1000000円」など）は拾わないよう、区切りつきの番号か携帯の11けただけ */
const PHONE = /(?<!\d)0\d{1,4}[-ー－ ]\d{1,4}[-ー－ ]\d{3,4}(?!\d)|(?<!\d)0[5789]0\d{8}(?!\d)|(?<!\d)01[016789]\d{7,8}(?!\d)|\+\d{1,3}[- ]?\d{2,4}[- ]?\d{3,4}[- ]?\d{3,4}/;
const EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/;

function normalize(text: string): string {
  // 全角英数を半角に、空白・記号をのぞく（「え ろ」「e.r.o」のような分け書きも拾う）
  return stripInvisible(text)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s　._・*＊\-~〜]/g, "");
}

/** 見えない字（ゼロ幅の文字・ソフトハイフンなど）を消す（要件#108: 「せ\u200bっくす」のように挟んですり抜けられないように） */
export function stripInvisible(text: string): string {
  return text.replace(/[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180B-\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFE00-\uFE0F\uFEFF\uFFA0]/g, "");
}

/** 英語の語は単語の区切りで見る（「cocktail」で「cock」を拾わない）。それ以外は区切りを消した文の中に含まれるかで見る */
const ASCII = /^[a-z ]+$/;
const asciiRe = new Map<string, RegExp>();
function hit(raw: string, norm: string, w: string): boolean {
  const lw = w.toLowerCase();
  if (ASCII.test(lw)) {
    let re = asciiRe.get(lw);
    if (!re) {
      re = new RegExp(`(?:^|[^a-z])${lw.replace(/ /g, "[\\s._*-]*")}(?:$|[^a-z])`);
      asciiRe.set(lw, re);
    }
    return re.test(raw);
  }
  return norm.includes(normalize(w));
}

export function keywordModeration(text: string): ModerationResult {
  const raw = stripInvisible(text).normalize("NFKC").toLowerCase();
  const t = normalize(text);
  if (SEXUAL.some((w) => hit(raw, t, w))) return { flagged: true, category: "sexual", by: "keyword" };
  if (HATE.some((w) => hit(raw, t, w))) return { flagged: true, category: "hate", by: "keyword" };
  if (PHONE.test(raw) || EMAIL.test(raw)) return { flagged: true, category: "personal_info", by: "keyword" };
  return { flagged: false, category: "none", by: "none" };
}

/** 発言を確かめる。seatKey は呼びすぎを防ぐためのキー（プレイヤーごと） */
export async function moderate(text: string, seatKey: string): Promise<ModerationResult> {
  if (text.trim() === "") return { flagged: false, category: "none", by: "none" };
  const k = keywordModeration(text);
  if (k.flagged) return k;
  if (!llmEnabled() || !allow(`mod:${seatKey}`, 30, 60_000)) return k;
  try {
    const r = await moderateWithLlm(text);
    if (r.inappropriate && r.category !== "none") return { flagged: true, category: r.category, by: "ai" };
  } catch (e) {
    log("moderation failed", String(e));
  }
  return { flagged: false, category: "none", by: "none" };
}
