// 対戦の不適切な発言の検出（要件#88）。
// 性的・アダルトな内容、差別、脅迫、個人情報（電話番号・住所など）を見つけたら、
// その発言は相手に見せず（伏せ字）、言った人に警告する。3回で負け（match.ts）。
// まずキーワードで見て、AI が使えるときは AI にも確かめさせる（AI が使えないときはキーワードだけ）。

import { llmEnabled, moderateWithLlm } from "./llm.ts";
import { allow } from "./ratelimit.ts";
import { log } from "./log.ts";

export type ModerationCategory = "sexual" | "hate" | "threat" | "personal_info" | "none";

export interface ModerationResult {
  flagged: boolean;
  category: ModerationCategory;
  by: "keyword" | "ai" | "none";
}

/** 性的・アダルトな言葉（伏せ字や言いかえもある程度拾う）。ゲームのクレームで普通は出ない言葉だけにする */
const SEXUAL: string[] = [
  "セックス", "せっくす", "えっち", "エッチ", "エロ", "えろい", "おっぱい", "ちんこ", "ちんぽ", "まんこ", "オナニー", "おなにー", "パンツ見せ", "裸を見せ", "脱げ", "ヤらせ", "やらせろ", "抱かせろ", "風俗", "援交", "AV女優", "下着見せ", "乳首", "射精", "勃起", "性行為",
  "sex", "porn", "nude", "naked", "boobs", "tits", "dick", "pussy", "cock", "blowjob", "horny", "masturbat", "strip for", "take off your clothes", "show me your",
  "做爱", "色情", "裸体", "脱衣", "胸部", "鸡巴", "阴茎", "阴道", "自慰", "援交", "约炮",
];
/** 差別・ひどい侮辱 */
const HATE: string[] = ["死ね", "しね", "殺す", "ころす", "キチガイ", "きちがい", "ガイジ", "がいじ", "kill yourself", "kys", "retard", "nigg", "faggot", "去死", "杀了你", "弱智"];
/** 個人情報らしいもの（電話番号・メールアドレス） */
const PHONE = /(?:0\d{1,4}[-ー－ ]?\d{1,4}[-ー－ ]?\d{3,4})|(?:\+?\d{2,3}[- ]?\d{3,4}[- ]?\d{4})/;
const EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/;

function normalize(text: string): string {
  // 全角英数を半角に、空白・記号をのぞく（「え ろ」「e.r.o」のような分け書きも拾う）
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s　._・*＊\-~〜]/g, "");
}

export function keywordModeration(text: string): ModerationResult {
  const raw = text.normalize("NFKC").toLowerCase();
  const t = normalize(text);
  if (SEXUAL.some((w) => t.includes(normalize(w)))) return { flagged: true, category: "sexual", by: "keyword" };
  if (HATE.some((w) => t.includes(normalize(w)))) return { flagged: true, category: "hate", by: "keyword" };
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
