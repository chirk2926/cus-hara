// 音声の文字起こし（Speech to Text）。音声対戦で、話した内容を判定に回すために使う。
// 方式は環境変数 STT_PROVIDER で選ぶ:
//   none              : 使わない（音声対戦は受け付けない）
//   openai_compatible : POST {STT_URL}/v1/audio/transcriptions（OpenAI 互換の文字起こしAPI。faster-whisper 系のサーバーなど）
//   whisper_cpp       : POST {STT_URL}/inference（whisper.cpp 付属の whisper-server）
//   mock              : テスト用。クライアントが付けた debug_text をそのまま返す
import { config } from "./config.ts";
import { wavFromPcm16 } from "./audio.ts";
import type { Lang } from "./lang.ts";

export class SttError extends Error {}

export function sttEnabled(): boolean {
  return config.sttProvider !== "none";
}

export async function transcribe(pcm: Int16Array, debugText?: string, lang: Lang = "ja"): Promise<string> {
  const provider = config.sttProvider;
  if (provider === "none") throw new SttError("このサーバーでは音声の文字起こしが使えません");
  if (provider === "mock") return (debugText ?? "").slice(0, 200);

  const wav = wavFromPcm16(pcm);
  const form = new FormData();
  form.append("file", new Blob([new Uint8Array(wav)], { type: "audio/wav" }), "voice.wav");
  let url: string;
  if (provider === "openai_compatible") {
    url = config.sttUrl.replace(/\/$/, "") + "/v1/audio/transcriptions";
    form.append("model", config.sttModel);
    form.append("language", lang);
    form.append("response_format", "json");
  } else {
    url = config.sttUrl.replace(/\/$/, "") + "/inference";
    form.append("language", lang);
    form.append("response_format", "json");
    form.append("temperature", "0.0");
  }
  const headers: Record<string, string> = {};
  if (config.sttApiKey) headers["Authorization"] = `Bearer ${config.sttApiKey}`;
  let res: Response;
  try {
    res = await fetch(url, { method: "POST", body: form, headers, signal: AbortSignal.timeout(config.sttTimeoutMs) });
  } catch {
    throw new SttError("文字起こしサーバーに接続できません");
  }
  if (!res.ok) throw new SttError(`文字起こしサーバーのエラー（${res.status}）`);
  const body = (await res.json()) as { text?: unknown };
  return typeof body.text === "string" ? body.text.trim().slice(0, 200) : "";
}
