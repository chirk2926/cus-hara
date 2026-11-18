// WebSocket でやりとりするメッセージの定義。Godot 側（scripts/net/server_api.gd）と合わせること。
// 一覧と説明は docs/SERVER.md の「WebSocket のメッセージ」。
import type { Player } from "./db.ts";
import { rankName } from "./rating.ts";
import type { Lang } from "./lang.ts";

export type Format = "text" | "voice";
export type Kind = "ranked" | "friend";
export type Role = "staff" | "customer";

export interface Conn {
  player: Player;
  lang: Lang;
  /** 接続元のIPアドレス（チート対策で、同じ回線どうしのランクマッチを避けるため） */
  ip: string;
  send(msg: Record<string, unknown>): void;
  close(code?: number, reason?: string): void;
}

export function publicPlayer(p: Player, rating?: number) {
  const r = rating ?? p.rating;
  return { id: p.id, name: p.name, rating: r, rank: rankName(r), wins: p.wins, losses: p.losses, draws: p.draws, title: p.title ?? "" };
}
