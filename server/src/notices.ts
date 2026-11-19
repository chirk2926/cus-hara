// お知らせの画像（要件#100）。管理画面から載せた画像を var/notice_images に置き、ゲームが /api/v1/notice_image/<名前> で読む。
// 中身が本当に PNG / JPEG かを先頭のバイトで確かめ、大きさは 2MB まで。名前はランダム（推測できない・パスを含まない）
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "./config.ts";

export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const NAME = /^[0-9a-f]{32}\.(png|jpg)$/;

function dir(): string {
  if (process.env.NOTICE_IMAGE_DIR) return process.env.NOTICE_IMAGE_DIR;
  if (config.dbPath === ":memory:") return path.join(process.env.TMPDIR ?? "/tmp", "cushara-notice-images");
  return path.join(path.dirname(config.dbPath), "notice_images");
}

export class ImageError extends Error {}

/** base64 の画像を保存して、名前を返す */
export function saveNoticeImage(b64: string): string {
  let bytes: Buffer;
  try {
    bytes = Buffer.from(b64, "base64");
  } catch {
    throw new ImageError("画像の形が正しくありません");
  }
  if (bytes.length === 0) throw new ImageError("画像が空です");
  if (bytes.length > MAX_IMAGE_BYTES) throw new ImageError("画像は 2MB までにしてください");
  let ext = "";
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) ext = "png";
  else if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) ext = "jpg";
  else throw new ImageError("PNG か JPEG の画像にしてください");
  const name = `${crypto.randomBytes(16).toString("hex")}.${ext}`;
  fs.mkdirSync(dir(), { recursive: true });
  fs.writeFileSync(path.join(dir(), name), bytes, { mode: 0o644 });
  return name;
}

/** 画像を読む（無ければ null） */
export function readNoticeImage(name: string): { bytes: Buffer; type: string } | null {
  if (!NAME.test(name)) return null;
  const p = path.join(dir(), name);
  if (!fs.existsSync(p)) return null;
  return { bytes: fs.readFileSync(p), type: name.endsWith(".png") ? "image/png" : "image/jpeg" };
}
