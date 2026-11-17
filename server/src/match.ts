// 対戦1試合の進行。判定・時間・得点・レーティングはすべてサーバーが決める（クライアントは入力と表示だけ）。
// ルールは docs/SPEC.md の 6節。
import crypto from "node:crypto";
import { config, scaled } from "./config.ts";
import { type Customer, type StageId, STAGES, randomCustomer, publicCustomer } from "./scenarios.ts";
import { judgeStaff, judgeCustomerLine } from "./keyword_judge.ts";
import { llmEnabled, generateCustomer, judgeStaffTurn, judgeCustomerTurn, type HistoryEntry } from "./llm.ts";
import { sttEnabled, transcribe } from "./stt.ts";
import { MAX_BYTES, mulawToPcm16, isNearlySilent } from "./audio.ts";
import { eloDelta, rankName } from "./rating.ts";
import { type Player, playerById, recordMatch } from "./db.ts";
import { allow } from "./ratelimit.ts";
import { type Conn, type Format, type Kind, type Role, publicPlayer } from "./protocol.ts";
import { log } from "./log.ts";
import type { Lang } from "./lang.ts";
import { isAllowed, judgeAction, actionLabel, actionAsStaffLine } from "./actions.ts";

interface Seat {
  player: Player;
  conn: Conn | null;
  ratingBefore: number;
  graceTimer: NodeJS.Timeout | null;
}

interface Input {
  text: string;
  via: "text" | "voice" | "timeout" | "action";
  action?: string;
  pcm?: Int16Array;
  debugText?: string;
}

interface Waiting {
  seat: number;
  phase: "customer_turn" | "staff_turn";
  resolve: (i: Input) => void;
  timer: NodeJS.Timeout;
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, scaled(ms)));
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export class Match {
  readonly id = crypto.randomUUID();
  readonly stage: StageId = STAGES[Math.floor(Math.random() * STAGES.length)];
  readonly seats: [Seat, Seat];
  finished = false;
  onEnd: ((m: Match) => void) | null = null;

  private totals: [number, number] = [0, 0];
  private waiting: Waiting | null = null;
  private usedTitles: string[] = [];
  // 表示中の状態（再接続したときに送り直す）
  private round = 0;
  private staffSeat = 0;
  private card: Customer | null = null;
  private anger = 0;
  private resolveVal = 0;
  private rate = 1;
  private phase: string = "intro";
  private phaseSeat = -1;
  private phaseStarted = 0;
  private phaseSeconds = 0;
  private transcript: Array<Record<string, unknown>> = [];

  readonly kind: Kind;
  readonly format: Format;
  readonly lang: Lang;

  /** 怒りの上がる速さの倍率（フレンド対戦で部屋を作った人の「返事の時間」。ランクマッチは 1） */
  rateScale = 1;

  constructor(kind: Kind, format: Format, lang: Lang, a: Conn, b: Conn) {
    this.kind = kind;
    this.format = format;
    this.lang = lang;
    this.seats = [
      { player: a.player, conn: a, ratingBefore: a.player.rating, graceTimer: null },
      { player: b.player, conn: b, ratingBefore: b.player.rating, graceTimer: null },
    ];
  }

  hasPlayer(id: string): number {
    return this.seats.findIndex((s) => s.player.id === id);
  }

  start(): void {
    log("match start", this.id, this.kind, this.format, this.seats.map((s) => s.player.name).join(" vs "));
    this.run().catch((e) => {
      log("match crashed", this.id, e);
      this.finish("server_error", -1);
    });
  }

  // ---------------------------------------------------------------- 送信

  private send(seat: number, msg: Record<string, unknown>): void {
    this.seats[seat].conn?.send(msg);
  }

  private who(seat: number, viewer: number): "you" | "opponent" {
    return seat === viewer ? "you" : "opponent";
  }

  private roleOf(seat: number): Role {
    return seat === this.staffSeat ? "staff" : "customer";
  }

  private sendPhase(): void {
    for (const v of [0, 1]) {
      this.send(v, {
        t: "phase",
        phase: this.phase,
        turn: this.phaseSeat < 0 ? "none" : this.who(this.phaseSeat, v),
        seconds: this.phaseSeconds,
        elapsed: (Date.now() - this.phaseStarted) / 1000 * config.timeScale,
        anger: this.anger,
        resolve: this.resolveVal,
        rate: this.phase === "staff_turn" ? this.rate : 0,
      });
    }
  }

  private matchFound(viewer: number): Record<string, unknown> {
    const me = this.seats[viewer];
    const op = this.seats[1 - viewer];
    return {
      t: "match_found",
      match_id: this.id,
      kind: this.kind,
      format: this.format,
      lang: this.lang,
      stage: this.stage,
      rounds: config.versus.rounds,
      you: publicPlayer(me.player, me.ratingBefore),
      opponent: publicPlayer(op.player, op.ratingBefore),
    };
  }

  private roundStart(viewer: number): Record<string, unknown> {
    return {
      t: "round_start",
      round: this.round,
      rounds: config.versus.rounds,
      role: this.roleOf(viewer),
      card: this.card ? publicCustomer(this.card) : null,
      anger: this.anger,
      resolve: this.resolveVal,
      rate: this.rate,
      totals: { you: this.totals[viewer], opponent: this.totals[1 - viewer] },
    };
  }

  // ---------------------------------------------------------------- 進行

  private async run(): Promise<void> {
    for (const v of [0, 1]) this.send(v, this.matchFound(v));
    await sleep(2500);
    if (this.finished) return;
    const first = Math.random() < 0.5 ? 0 : 1;
    for (let r = 0; r < config.versus.rounds; r++) {
      const staff = r % 2 === 0 ? first : 1 - first;
      const res = await this.playRound(r, staff);
      if (this.finished || res === null) return;
      this.totals[res.winner] += res.points;
    }
    const winner = this.totals[0] === this.totals[1] ? -1 : this.totals[0] > this.totals[1] ? 0 : 1;
    this.finish("completed", winner === -1 ? -1 : 1 - winner, winner === -1);
  }

  private async pickCard(): Promise<Customer> {
    if (llmEnabled()) {
      try {
        const timeout = new Promise<null>((r) => setTimeout(() => r(null), 12000));
        const c = await Promise.race([generateCustomer(this.stage, this.usedTitles, this.lang), timeout]);
        if (c) return c;
      } catch (e) {
        log("card generation failed, using scenario", String(e));
      }
    }
    return randomCustomer(this.stage, this.usedTitles, this.lang);
  }

  private async playRound(r: number, staff: number): Promise<{ winner: number; points: number } | null> {
    const customer = 1 - staff;
    this.round = r;
    this.staffSeat = staff;
    this.phase = "intro";
    this.phaseSeat = -1;
    this.transcript = [];
    const card = await this.pickCard();
    if (this.finished) return null;
    this.card = card;
    this.usedTitles.push(card.title);
    this.anger = card.start_anger;
    this.resolveVal = 0;
    this.rate = config.versus.baseAngerRate * card.patience * this.rateScale;
    for (const v of [0, 1]) this.send(v, this.roundStart(v));
    await sleep(config.versus.roundIntroMs);
    if (this.finished) return null;

    const history: HistoryEntry[] = [];
    const usedStaff: string[] = [];
    const usedCustomer: string[] = [];
    let exchanges = 0;
    let outcome = "";
    const voiceExtra = this.format === "voice" ? config.versus.voiceExtraSec : 0;

    // 客役の最初のクレーム（空・時間切れならカードの文面を使う。ペナルティなし）
    let opening = await this.waitInput(customer, "customer_turn", config.versus.openingSec + voiceExtra);
    if (this.finished) return null;
    let openingText = await this.inputToText(customer, opening, "customer");
    if (this.finished) return null;
    if (openingText === "") openingText = card.opening;
    usedCustomer.push(openingText);
    history.push({ role: "customer", text: openingText });
    this.broadcastLine("customer", customer, openingText, opening.via);
    await sleep(this.lineTime(openingText));
    if (this.finished) return null;

    while (outcome === "") {
      // ---- 店員の番: 考えている間、怒りが上がる。100で時間切れ
      const staffSeconds = (100 - this.anger) / this.rate + voiceExtra;
      const startAnger = this.anger;
      const input = await this.waitInput(staff, "staff_turn", staffSeconds);
      if (this.finished) return null;
      const elapsed = Math.min(input.via === "timeout" ? Infinity : this.elapsedSec(), staffSeconds);
      this.anger = clamp(startAnger + this.rate * Math.max(0, elapsed - voiceExtra), 0, 100);
      if (input.via === "timeout" || this.anger >= 100) {
        this.anger = 100;
        outcome = "explode";
        this.broadcastJudged(0, 0, this.lang === "ja" ? "時間切れ！お客さんがキレた。" : "Time's up! The customer snapped.", "staff");
        break;
      }
      this.setPhase("judging", -1, 0);
      if (input.via === "action" && input.action) {
        // 店の行動ボタン（要件#34）: 点数は表どおり
        const j = judgeAction(card, input.action, this.anger, this.resolveVal, this.lang);
        const label = actionAsStaffLine(input.action, this.lang);
        history.push({ role: "staff", text: label });
        this.broadcastLine("staff", staff, label, "action");
        this.anger = clamp(this.anger + j.anger_delta, 0, 100);
        this.resolveVal = clamp(this.resolveVal + j.resolve_delta, 0, 100);
        this.broadcastJudged(j.anger_delta, j.resolve_delta, j.comment, "staff");
        if (j.yielded) outcome = "yield";
        else if (this.anger >= 100) outcome = "explode";
        else if (this.resolveVal >= 100) outcome = "resolved";
        if (outcome !== "") break;
        exchanges++;
        await sleep(config.versus.pauseAfterLineMs);
        if (this.finished) return null;
        continue;
      }
      const reply = await this.inputToText(staff, input, "staff");
      if (this.finished) return null;
      if (reply === "") {
        // 声が聞き取れなかった: 少し怒りが上がり、もう一度店員の番
        this.anger = clamp(this.anger + 5, 0, 100);
        this.broadcastJudged(5, 0, this.lang === "ja" ? "よく聞き取れなかった…もう一度！" : "Didn't catch that... try again!", "staff");
        if (this.anger >= 100) { outcome = "explode"; break; }
        continue;
      }
      history.push({ role: "staff", text: reply });
      this.broadcastLine("staff", staff, reply, input.via);
      const j = await this.judgeStaff(card, reply, usedStaff, history, input.via === "voice", staff);
      if (this.finished) return null;
      usedStaff.push(reply);
      this.anger = clamp(this.anger + j.anger_delta, 0, 100);
      this.resolveVal = clamp(this.resolveVal + j.resolve_delta, 0, 100);
      this.broadcastJudged(j.anger_delta, j.resolve_delta, j.comment, "staff");
      if (j.yielded) outcome = "yield";
      else if (this.anger >= 100) outcome = "explode";
      else if (this.resolveVal >= 100) outcome = "resolved";
      if (outcome !== "") break;
      exchanges++;
      if (exchanges >= config.versus.maxExchanges) {
        outcome = this.resolveVal > this.anger ? "resolved" : "explode";
        break;
      }
      await sleep(config.versus.pauseAfterLineMs);
      if (this.finished) return null;

      // ---- 客役の番: 言い返す
      const cin = await this.waitInput(customer, "customer_turn", config.versus.customerSec + voiceExtra);
      if (this.finished) return null;
      this.setPhase("judging", -1, 0);
      const line = await this.inputToText(customer, cin, "customer");
      if (this.finished) return null;
      const shown = line !== "" ? line : this.lang === "ja" ? "……（言葉に詰まっている）" : "... (lost for words)";
      history.push({ role: "customer", text: shown });
      this.broadcastLine("customer", customer, shown, cin.via);
      const cj = await this.judgeCustomer(card, line, usedCustomer, history, cin.via === "voice", customer);
      if (this.finished) return null;
      if (line !== "") usedCustomer.push(line);
      this.anger = clamp(this.anger + cj.anger_delta, 0, 100);
      this.resolveVal = clamp(this.resolveVal + cj.resolve_delta, 0, 100);
      this.broadcastJudged(cj.anger_delta, cj.resolve_delta, cj.comment, "customer");
      if (this.resolveVal >= 100) outcome = "resolved";
      else if (this.anger >= 100) outcome = "explode";
      await sleep(this.lineTime(shown));
      if (this.finished) return null;
    }

    const winner = outcome === "resolved" ? staff : customer;
    const points = outcome === "resolved" ? 100 + Math.round(100 - this.anger) : 100 + Math.round(100 - this.resolveVal);
    this.totals[winner] += 0; // 合計は run() で加算する
    this.setPhase("round_end", -1, 0);
    for (const v of [0, 1]) {
      this.send(v, {
        t: "round_end",
        outcome,
        winner: this.who(winner, v),
        points,
        staff: this.who(staff, v),
        totals: {
          you: this.totals[v] + (winner === v ? points : 0),
          opponent: this.totals[1 - v] + (winner === 1 - v ? points : 0),
        },
      });
    }
    await sleep(config.versus.roundOutroMs);
    return { winner, points };
  }

  private lineTime(text: string): number {
    return Math.min(Math.max(text.length * 45, 500), 3600) + 600;
  }

  private elapsedSec(): number {
    return ((Date.now() - this.phaseStarted) / 1000) * config.timeScale;
  }

  private setPhase(phase: string, seat: number, seconds: number): void {
    this.phase = phase;
    this.phaseSeat = seat;
    this.phaseStarted = Date.now();
    this.phaseSeconds = seconds;
    this.sendPhase();
  }

  private waitInput(seat: number, phase: "customer_turn" | "staff_turn", seconds: number): Promise<Input> {
    this.setPhase(phase, seat, seconds);
    return new Promise<Input>((resolve) => {
      const timer = setTimeout(() => {
        if (this.waiting?.timer === timer) {
          this.waiting = null;
          resolve({ text: "", via: "timeout" });
        }
      }, scaled(seconds * 1000));
      this.waiting = { seat, phase, resolve, timer };
    });
  }

  private resolveWaiting(input: Input): void {
    const w = this.waiting;
    if (!w) return;
    clearTimeout(w.timer);
    this.waiting = null;
    w.resolve(input);
  }

  /** 入力を文字にする。音声なら相手に声を中継し、文字起こしする */
  private async inputToText(seat: number, input: Input, role: Role): Promise<string> {
    if (input.via !== "voice" || !input.pcm) return input.text;
    if (isNearlySilent(input.pcm) && input.debugText === undefined) return "";
    try {
      return (await transcribe(input.pcm, input.debugText, this.lang)).trim();
    } catch (e) {
      log("stt failed", String(e));
      this.send(seat, { t: "notice", text: this.lang === "ja" ? "声を文字にできませんでした。もう一度話すか、文字で入力してください。" : "Couldn't make out your voice. Speak again or type your line." });
      void role;
      return "";
    }
  }

  private async judgeStaff(card: Customer, reply: string, used: string[], history: HistoryEntry[], voice: boolean, seat: number) {
    if (llmEnabled() && allow(`llm:${this.seats[seat].player.id}`, config.llmPerMinute * 2, 60_000)) {
      try {
        return await judgeStaffTurn(this.stage, card, history, this.anger, this.resolveVal, voice, this.lang);
      } catch (e) {
        log("llm judge failed", String(e));
      }
    }
    return judgeStaff(card, reply, used, this.anger, this.resolveVal, this.lang);
  }

  private async judgeCustomer(card: Customer, line: string, used: string[], history: HistoryEntry[], voice: boolean, seat: number) {
    if (line !== "" && llmEnabled() && allow(`llm:${this.seats[seat].player.id}`, config.llmPerMinute * 2, 60_000)) {
      try {
        return await judgeCustomerTurn(this.stage, card, history, voice, this.lang);
      } catch (e) {
        log("llm customer judge failed", String(e));
      }
    }
    return judgeCustomerLine(card, line, used, this.lang);
  }

  private broadcastLine(role: Role, seat: number, text: string, via: string): void {
    const entry = { role, text, via };
    this.transcript.push(entry);
    for (const v of [0, 1]) this.send(v, { t: "line", ...entry, by: this.who(seat, v) });
  }

  private broadcastJudged(angerDelta: number, resolveDelta: number, comment: string, about: Role): void {
    for (const v of [0, 1]) {
      this.send(v, { t: "judged", anger: this.anger, resolve: this.resolveVal, anger_delta: angerDelta, resolve_delta: resolveDelta, comment, about });
    }
  }

  // ---------------------------------------------------------------- 入力の受け口

  onSay(seat: number, raw: unknown): void {
    const text = typeof raw === "string" ? raw.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 200) : "";
    if (!this.waiting || this.waiting.seat !== seat || text === "") return;
    this.resolveWaiting({ text, via: "text" });
  }

  /** 店員役が店の行動ボタンを押した */
  onAction(seat: number, raw: unknown): void {
    if (!this.waiting || this.waiting.seat !== seat || this.waiting.phase !== "staff_turn" || !this.card) return;
    const id = typeof raw === "string" ? raw : "";
    if (id.startsWith("crane_") || !isAllowed(this.stage, this.card, id)) return;
    this.resolveWaiting({ text: actionLabel(id, this.lang), via: "action", action: id });
  }

  onVoice(seat: number, b64: unknown, debugText: unknown): void {
    if (this.format !== "voice" || !this.waiting || this.waiting.seat !== seat || typeof b64 !== "string") return;
    let bytes: Buffer;
    try {
      bytes = Buffer.from(b64, "base64");
    } catch {
      return;
    }
    if (bytes.length < 1600 || bytes.length > MAX_BYTES) {
      this.send(seat, { t: "notice", text: this.lang === "ja" ? "声が短すぎるか長すぎます（0.1〜20秒）。" : "Voice clip is too short or too long (0.1–20 s)." });
      return;
    }
    // 相手にはすぐ声を届ける（ボイスチャットとして聞こえる）
    const role = this.roleOf(seat);
    this.send(1 - seat, { t: "voice", role, by: "opponent", audio: b64 });
    const debug = config.sttProvider === "mock" && typeof debugText === "string" ? debugText : undefined;
    this.resolveWaiting({ text: "", via: "voice", pcm: mulawToPcm16(new Uint8Array(bytes)), debugText: debug });
  }

  // ---------------------------------------------------------------- 切断・再接続・終了

  onDisconnect(seat: number): void {
    const s = this.seats[seat];
    s.conn = null;
    if (this.finished) return;
    this.send(1 - seat, { t: "opponent_status", connected: false, grace_seconds: config.versus.reconnectGraceMs / 1000 });
    s.graceTimer = setTimeout(() => this.forfeit(seat, "disconnected"), config.versus.reconnectGraceMs);
  }

  onReconnect(seat: number, conn: Conn): void {
    const s = this.seats[seat];
    if (s.graceTimer) clearTimeout(s.graceTimer);
    s.graceTimer = null;
    s.conn = conn;
    this.send(seat, this.matchFound(seat));
    if (this.card) this.send(seat, this.roundStart(seat));
    for (const entry of this.transcript) {
      const by = (entry.role === "staff") === (seat === this.staffSeat) ? "you" : "opponent";
      this.send(seat, { t: "line", ...entry, by, replay: true });
    }
    this.sendPhase();
    this.send(1 - seat, { t: "opponent_status", connected: true });
  }

  forfeit(seat: number, reason: string): void {
    if (this.finished) return;
    this.finish(reason, seat);
  }

  /** loser: 負けた（または途中で抜けた）側の席。-1 なら引き分け／記録しない */
  private finish(reason: string, loser: number, draw = false): void {
    if (this.finished) return;
    this.finished = true;
    if (this.waiting) {
      clearTimeout(this.waiting.timer);
      const w = this.waiting;
      this.waiting = null;
      w.resolve({ text: "", via: "timeout" });
    }
    for (const s of this.seats) if (s.graceTimer) clearTimeout(s.graceTimer);

    let winnerSeat = -1;
    if (!draw && loser >= 0) winnerSeat = 1 - loser;
    const recordable = reason !== "server_error";
    const deltas: [number, number] = [0, 0];
    if (this.kind === "ranked" && recordable) {
      for (const v of [0, 1]) {
        const score = winnerSeat === -1 ? 0.5 : winnerSeat === v ? 1 : 0;
        deltas[v] = eloDelta(this.seats[v].ratingBefore, this.seats[1 - v].ratingBefore, score);
      }
    }
    if (recordable) {
      try {
        recordMatch({
          id: this.id,
          kind: this.kind,
          format: this.format,
          stage: this.stage,
          p1: this.seats[0].player.id,
          p2: this.seats[1].player.id,
          p1Points: this.totals[0],
          p2Points: this.totals[1],
          winner: winnerSeat === -1 ? null : this.seats[winnerSeat].player.id,
          p1Delta: deltas[0],
          p2Delta: deltas[1],
          endedReason: reason,
        });
      } catch (e) {
        log("record match failed", e);
      }
    }
    for (const v of [0, 1]) {
      const fresh = playerById(this.seats[v].player.id) ?? this.seats[v].player;
      const after = fresh.rating;
      this.send(v, {
        t: "match_end",
        reason,
        kind: this.kind,
        result: winnerSeat === -1 ? "draw" : winnerSeat === v ? "win" : "lose",
        you_points: this.totals[v],
        opponent_points: this.totals[1 - v],
        rating_before: this.seats[v].ratingBefore,
        rating_after: after,
        rating_delta: deltas[v],
        rank: rankName(after),
        player: publicPlayer(fresh),
      });
    }
    log("match end", this.id, reason, "winner seat", winnerSeat, "totals", this.totals.join("-"));
    this.onEnd?.(this);
  }
}
