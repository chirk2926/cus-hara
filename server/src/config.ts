// サーバーの設定。すべて環境変数で変える（docs/SERVER.md に一覧）。
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

function num(name: string, def: number): number {
  const v = process.env[name];
  if (v === undefined || v === "") return def;
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

function str(name: string, def: string): string {
  const v = process.env[name];
  return v === undefined || v === "" ? def : v;
}

export type LlmMode = "auto" | "claude" | "offline";
export type SttProvider = "none" | "openai_compatible" | "whisper_cpp" | "mock";

export const config = {
  port: num("PORT", 8787),
  host: str("HOST", "0.0.0.0"),
  // データベース（SQLite）のファイル。":memory:" でメモリ上（テスト用）
  dbPath: str("DB_PATH", path.join(here, "..", "var", "cushara.db")),
  scenariosPath: str("SCENARIOS_PATH", path.join(here, "..", "..", "data", "scenarios.json")),

  // AI: auto = APIキーがあれば Claude、なければキーワード判定 / claude = 必ず Claude / offline = 使わない
  llmMode: str("LLM_MODE", "auto") as LlmMode,
  model: str("CLAUDE_MODEL", "claude-opus-5-5"),
  llmTimeoutMs: num("LLM_TIMEOUT_MS", 45000),

  // 音声の文字起こし（音声対戦に必要）
  sttProvider: str("STT_PROVIDER", "none") as SttProvider,
  sttUrl: str("STT_URL", "http://127.0.0.1:8080"),
  sttModel: str("STT_MODEL", "whisper-1"),
  sttApiKey: str("STT_API_KEY", ""),
  sttTimeoutMs: num("STT_TIMEOUT_MS", 30000),

  // 1人のプレイヤーが1分間に使える AI 呼び出しの回数（運営側の API 料金を守るため）
  llmPerMinute: num("LLM_PER_MINUTE", 20),
  // 1つのIPアドレスから1時間に作れるゲストアカウントの数
  guestsPerHour: num("GUESTS_PER_HOUR", 20),

  // 対戦のルール（数値の意味は docs/SPEC.md の対戦モード）
  versus: {
    rounds: 2,
    openingSec: num("VS_OPENING_SEC", 35),
    customerSec: num("VS_CUSTOMER_SEC", 25),
    voiceExtraSec: num("VS_VOICE_EXTRA_SEC", 10),
    maxExchanges: 8,
    baseAngerRate: 1.1,
    pauseAfterLineMs: num("VS_PAUSE_MS", 1600),
    roundIntroMs: num("VS_ROUND_INTRO_MS", 5000),
    roundOutroMs: num("VS_ROUND_OUTRO_MS", 5500),
    reconnectGraceMs: num("VS_RECONNECT_GRACE_MS", 20000),
  },
  // マッチングの許容レーティング差: start から毎秒 growPerSec ずつ広げ、anyoneAfterSec 秒で誰とでも組む
  match: {
    startWindow: 100,
    growPerSec: 15,
    anyoneAfterSec: num("MM_ANYONE_AFTER_SEC", 45),
  },
  // テストで時間を速めるための倍率（1 = 通常）
  timeScale: num("TIME_SCALE", 1),
};

export function scaled(ms: number): number {
  return Math.max(1, Math.round(ms / config.timeScale));
}
