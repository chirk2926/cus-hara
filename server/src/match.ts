// 対戦1試合の進行。判定・時間・得点・レーティングはすべてサーバーが決める（クライアントは入力と表示だけ）。
// ルールは docs/SPEC.md の 6節。
import { runtime } from "./settings.ts";
import { trackMatch, endMatch, markReported } from "./matchlogs.ts";
import crypto from "node:crypto";
import { config, scaled } from "./config.ts";
import { type Customer, type StageId, STAGES, randomCustomer, publicCustomer } from "./scenarios.ts";
import { openStages } from "./stages.ts";
import { judgeStaff, judgeCustomerLine } from "./keyword_judge.ts";
import { llmEnabled, generateCustomer, judgeStaffTurn, judgeCustomerTurn, type HistoryEntry } from "./llm.ts";
import { sttEnabled, transcribe } from "./stt.ts";
import { MAX_BYTES, mulawToPcm16, isNearlySilent } from "./audio.ts";
import { eloDelta, rankName } from "./rating.ts";
import { type Player, playerById, recordMatch, recentPairCount, addReport } from "./db.ts";
import { moderate, keywordModeration, type ModerationCategory } from "./moderation.ts";
import { allow } from "./ratelimit.ts";
import { type Conn, type Format, type Kind, type Role, publicPlayer } from "./protocol.ts";
import { log } from "./log.ts";
import { type Lang, pick } from "./lang.ts";
import { isAllowed, judgeAction, actionLabel, actionAsStaffLine, CRANE_RESULTS, applyProblem } from "./actions.ts";

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
  readonly stage: StageId = pickStage();
  readonly seats: [Seat, Seat];
  finished = false;
  onEnd: ((m: Match) => void) | null = null;

  private totals: [number, number] = [0, 0];
  /** 不適切な発言の回数（要件#88）。MOD_MAX 回で負け */
  private strikes: [number, number] = [0, 0];
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
  /** 試合全体の会話（通報されたときだけ保存する。要件#100） */
  private fullLog: Array<Record<string, unknown>> = [];

  readonly kind: Kind;
  readonly format: Format;
  readonly lang: Lang;

  /** 怒りの上がる速さの倍率（フレンド対戦で部屋を作った人の「返事の時間」。ランクマッチは 1） */
  rateScale = 1;
  /** 席ごとに、実際に発言・行動した回数（すぐ抜けた試合の判定に使う） */
  private inputs: [number, number] = [0, 0];
  /** レーティングが動かなかった理由（結果画面に出す） */
  private ratingNote = "";

  constructor(kind: Kind, format: Format, lang: Lang, a: Conn, b: Conn) {
    this.kind = kind;
    this.format = format;
    this.lang = lang;
    this.seats = [
      { player: a.player, conn: a, ratingBefore: (playerById(a.player.id) ?? a.player).rating, graceTimer: null },
      { player: b.player, conn: b, ratingBefore: (playerById(b.player.id) ?? b.player).rating, graceTimer: null },
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
      // 声の対戦は EOS のボイスで相手に届ける（要件#100）。部屋を作るのは席 0 の人。だめならサーバーが中継する
      voice_host: this.format === "voice" && viewer === 0,
      voice_mode: this.eosVoice ? "eos" : "relay",
    };
  }

  // ---------------------------------------------------------------- EOS のボイス（要件#100）
  /** 両方が EOS のボイスの部屋につながった。声はサーバーで中継しない（文字起こしには使う） */
  private eosVoice = false;
  private eosReady: [boolean, boolean] = [false, false];

  /** 席 0 が作った EOS のボイスの部屋の ID を、相手に渡す */
  onEosVoiceRoom(seat: number, lobbyId: unknown): void {
    if (this.format !== "voice" || seat !== 0 || typeof lobbyId !== "string") return;
    const id = lobbyId.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 128);
    if (id === "") return;
    this.send(1, { t: "eos_voice", lobby_id: id });
  }

  /** EOS のボイスの部屋につながった／切れた */
  onEosVoiceReady(seat: number, ok: unknown): void {
    if (this.format !== "voice") return;
    this.eosReady[seat] = ok === true;
    const next = this.eosReady[0] && this.eosReady[1];
    if (next !== this.eosVoice) {
      this.eosVoice = next;
      for (const v of [0, 1]) this.send(v, { t: "voice_mode", mode: next ? "eos" : "relay" });
      log("voice mode", this.id, next ? "eos" : "relay");
    }
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
        if (c) return applyProblem(c);
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
    else {
      const sc = await this.screen(customer, openingText);
      if (this.finished) return null;
      if (sc.flagged) {
        openingText = sc.text;
        this.resolveVal = clamp(this.resolveVal + 15, 0, 100);
      }
    }
    usedCustomer.push(openingText);
    history.push({ role: "customer", text: openingText });
    this.broadcastLine("customer", customer, openingText, opening.via);
    await sleep(this.lineTime(openingText));
    if (this.finished) return null;

    let timedOut = false; // 店員が時間切れで負けた（称号「無言の圧」用。要件#81）
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
        timedOut = true;
        this.broadcastJudged(0, 0, pick(this.lang, { ja: "時間切れ！お客さんがキレた。", en: "Time's up! The customer snapped.", zh: "时间到！顾客发飙了。", ko: "시간 초과! 손님이 폭발했다." }), "staff");
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
        this.broadcastJudged(5, 0, pick(this.lang, { ja: "よく聞き取れなかった…もう一度！", en: "Didn't catch that... try again!", zh: "没听清……再说一遍！", ko: "잘 안 들렸어… 한 번 더!" }), "staff");
        if (this.anger >= 100) { outcome = "explode"; break; }
        continue;
      }
      // 不適切な発言（要件#88）: 相手には伏せ字で見せ、採点はせずに怒りを大きく上げる。
      // まずキーワードで見て、通ったら AI の採点と同じ1回の呼び出しで AI にも確かめさせる（呼び出しを2回から1回に。要件#93）
      const kw = keywordModeration(reply);
      let flag: ModerationCategory = kw.flagged ? kw.category : "none";
      let j = null;
      if (flag === "none") {
        history.push({ role: "staff", text: reply });
        j = await this.judgeStaff(card, reply, usedStaff, history, input.via === "voice", staff);
        if (this.finished) return null;
        if (j.flag !== undefined && j.flag !== "none") {
          flag = j.flag;
          history.pop();
        }
      }
      if (flag !== "none" || j === null) {
        const masked = this.strike(staff, flag, kw.flagged ? "keyword" : "ai", reply);
        if (this.finished) return null;
        history.push({ role: "staff", text: masked });
        this.broadcastLine("staff", staff, masked, input.via);
        this.anger = clamp(this.anger + 25, 0, 100);
        this.broadcastJudged(25, 0, pick(this.lang, { ja: "不適切な発言。お客さんが激怒した。", en: "Inappropriate remark. The customer is furious.", zh: "不当发言。顾客暴怒了。", ko: "부적절한 발언. 손님이 격노했다." }), "staff");
        if (this.anger >= 100) { outcome = "explode"; break; }
        await sleep(config.versus.pauseAfterLineMs);
        if (this.finished) return null;
        continue;
      }
      this.broadcastLine("staff", staff, reply, input.via);
      usedStaff.push(reply);
      // 対戦は1回の返事で決まりすぎないように、納得の増え方は 40 まで（1人用は話がまとまれば一気に埋めてよい。要件#106）
      j.resolve_delta = Math.min(j.resolve_delta, 40);
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
      let shown = line !== "" ? line : pick(this.lang, { ja: "……（言葉に詰まっている）", en: "... (lost for words)", zh: "……（说不出话来）", ko: "……(말문이 막혔다)" });
      // 不適切な発言の確かめ方は店員の番と同じ（キーワード → AI の採点と一緒に。要件#88, #93）
      const ckw = line !== "" ? keywordModeration(line) : { flagged: false, category: "none" as ModerationCategory };
      let cflag: ModerationCategory = ckw.flagged ? ckw.category : "none";
      let cj = null;
      if (cflag === "none") {
        history.push({ role: "customer", text: shown });
        cj = await this.judgeCustomer(card, line, usedCustomer, history, cin.via === "voice", customer);
        if (this.finished) return null;
        if (cj.flag !== undefined && cj.flag !== "none") {
          cflag = cj.flag;
          history.pop();
        }
      }
      if (cflag !== "none" || cj === null) {
        shown = this.strike(customer, cflag, ckw.flagged ? "keyword" : "ai", line);
        if (this.finished) return null;
        history.push({ role: "customer", text: shown });
        cj = { anger_delta: 0, resolve_delta: 15, comment: pick(this.lang, { ja: "不適切な発言。店員側に有利になった。", en: "Inappropriate remark. Advantage to the clerk.", zh: "不当发言。对店员有利。", ko: "부적절한 발언. 직원 쪽이 유리해졌다." }) };
      }
      this.broadcastLine("customer", customer, shown, cin.via);
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
        timeout: timedOut,
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
      this.send(seat, { t: "notice", text: pick(this.lang, { ja: "声を文字にできませんでした。もう一度話すか、文字で入力してください。", en: "Couldn't make out your voice. Speak again or type your line.", zh: "没能识别你的声音。请再说一次，或用文字输入。", ko: "목소리를 글자로 바꾸지 못했습니다. 다시 말하거나 글자로 입력하세요." }) });
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
    this.fullLog.push({ round: this.round, role, by: this.seats[seat].player.id, name: this.seats[seat].player.name, text, via, at: Date.now() });
    trackMatch(this.id, this.logBody());
    for (const v of [0, 1]) this.send(v, { t: "line", ...entry, by: this.who(seat, v) });
  }

  private broadcastJudged(angerDelta: number, resolveDelta: number, comment: string, about: Role): void {
    for (const v of [0, 1]) {
      this.send(v, { t: "judged", anger: this.anger, resolve: this.resolveVal, anger_delta: angerDelta, resolve_delta: resolveDelta, comment, about });
    }
  }

  // ---------------------------------------------------------------- 入力の受け口

  onSay(seat: number, raw: unknown): void {
    const text = typeof raw === "string" ? raw.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 256) : "";
    if (!this.waiting || this.waiting.seat !== seat || text === "") return;
    this.inputs[seat]++;
    this.resolveWaiting({ text, via: "text" });
  }

  /** 店員役が店の行動ボタンを押した */
  onAction(seat: number, raw: unknown): void {
    if (!this.waiting || this.waiting.seat !== seat || this.waiting.phase !== "staff_turn" || !this.card) return;
    const id = typeof raw === "string" ? raw : "";
    // 対戦には台の調整のミニゲームが無いので、その結果（crane_won / crane_lost）だけは受け付けない。
    // 「引っかかった景品をとる」（crane_stuck）は使える（以前は crane_ で始まる行動をすべて断っていたバグ）
    if ((CRANE_RESULTS as readonly string[]).includes(id) || !isAllowed(this.stage, this.card, id, true)) return;
    this.inputs[seat]++;
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
      this.send(seat, { t: "notice", text: pick(this.lang, { ja: "声が短すぎるか長すぎます（0.1〜20秒）。", en: "Voice clip is too short or too long (0.1–20 s).", zh: "语音太短或太长（0.1～20秒）。", ko: "음성이 너무 짧거나 깁니다 (0.1~20초)." }) });
      // 番は続いているので、入力できる状態に戻してもらう
      this.sendPhase();
      return;
    }
    // 相手にはすぐ声を届ける（ボイスチャットとして聞こえる）。EOS のボイスで届いているときは、サーバーからは送らない（要件#100）
    const role = this.roleOf(seat);
    if (!this.eosVoice) this.send(1 - seat, { t: "voice", role, by: "opponent", audio: b64 });
    const debug = config.sttProvider === "mock" && typeof debugText === "string" ? debugText : undefined;
    this.inputs[seat]++;
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

  /** 不適切な発言を確かめる（要件#88）。最初のクレームのように AI の採点がない発言に使う。見つけたら伏せ字の文を返す */
  private async screen(seat: number, text: string): Promise<{ text: string; flagged: boolean }> {
    const m = await moderate(text, this.seats[seat].player.id);
    if (!m.flagged) return { text, flagged: false };
    return { text: this.strike(seat, m.category, m.by, text), flagged: true };
  }

  /** 不適切な発言が見つかったとき: 言った人に警告し、自動で通報を残す。MOD_MAX 回で負け。伏せ字の文を返す */
  private strike(seat: number, category: ModerationCategory, by: string, text: string): string {
    const m = { category, by };
    this.strikes[seat]++;
    const masked = pick(this.lang, { ja: "（不適切な発言のため表示しません）", en: "(Hidden: inappropriate remark)", zh: "（不当发言，已隐藏）", ko: "(부적절한 발언이라 표시하지 않습니다)" });
    const reason = REPORT_OF[m.category];
    addReport("system:moderation", this.seats[seat].player.id, this.id, reason, `auto(${m.by}) ${text.slice(0, 120)}`);
    markReported(this.id);
    log("moderation", this.id, "seat", seat, m.category, m.by, "strike", this.strikes[seat]);
    const left = modMax() - this.strikes[seat];
    this.send(seat, {
      t: "warning",
      category: m.category,
      strikes: this.strikes[seat],
      max: modMax(),
      text: left > 0
        ? pick(this.lang, { ja: `警告: 不適切な発言です（${CATEGORY_JA[m.category]}）。あと${left}回で負けになります。`, en: `Warning: inappropriate remark (${m.category}). ${left} more and you lose.`, zh: `警告：不当发言（${m.category}）。再有${left}次将判负。`, ko: `경고: 부적절한 발언입니다 (${m.category}). ${left}번 더 하면 패배합니다.` })
        : pick(this.lang, { ja: "不適切な発言が続いたため、負けになりました。", en: "Too many inappropriate remarks. You lose.", zh: "不当发言过多，判负。", ko: "부적절한 발언이 계속되어 패배했습니다." }),
    });
    this.send(1 - seat, { t: "notice", text: pick(this.lang, { ja: "相手の不適切な発言を伏せました。", en: "An inappropriate remark from your opponent was hidden.", zh: "已隐藏对手的不当发言。", ko: "상대의 부적절한 발언을 가렸습니다." }) });
    if (this.strikes[seat] >= modMax()) this.forfeit(seat, "moderation");
    return masked;
  }

  forfeit(seat: number, reason: string): void {
    if (this.finished) return;
    this.finish(reason, seat);
  }

  /** loser: 負けた（または途中で抜けた）側の席。-1 なら引き分け／記録しない */
  private logBody(): Record<string, unknown> {
    return {
      match_id: this.id, kind: this.kind, format: this.format, stage: this.stage, lang: this.lang,
      players: this.seats.map((s) => ({ id: s.player.id, name: s.player.name })), lines: this.fullLog,
    };
  }

  private finish(reason: string, loser: number, draw = false): void {
    if (this.finished) return;
    this.finished = true;
    trackMatch(this.id, { ...this.logBody(), ended_reason: reason });
    endMatch(this.id);
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
      // チート対策（要件#47）
      // 1. 同じ相手と24時間で何度も当たっている → レーティングを動かさない（なれあい・稼ぎ）
      if (recentPairCount(this.seats[0].player.id, this.seats[1].player.id) >= config.samePairLimit24h) {
        deltas[0] = 0;
        deltas[1] = 0;
        this.ratingNote = "same_pair";
      }
      // 2. 誰も発言しないうちに抜けた試合 → 勝った側は上がらない（抜けた側は下がる）
      if ((reason === "left" || reason === "disconnected") && this.inputs[0] + this.inputs[1] === 0 && winnerSeat >= 0) {
        deltas[winnerSeat] = 0;
        if (this.ratingNote === "") this.ratingNote = "early_leave";
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
      // 同じ接続で「もう一戦」したとき古いレートを使わないよう、接続の持つプレイヤー情報も新しくする
      const c = this.seats[v].conn;
      if (c) Object.assign(c.player, fresh);
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
        rating_note: this.ratingNote,
        rank: rankName(after),
        player: publicPlayer(fresh),
      });
    }
    log("match end", this.id, reason, "winner seat", winnerSeat, "totals", this.totals.join("-"));
    this.onEnd?.(this);
  }
}

/** 不適切な発言で負けになる回数（要件#88） */
/** 不適切な発言で負けになる回数（管理画面で変えられる。要件#100） */
const modMax = () => runtime.modMax;
const REPORT_OF: Record<ModerationCategory, "sexual" | "abuse" | "personal_info" | "other"> = {
  sexual: "sexual", hate: "abuse", threat: "abuse", personal_info: "personal_info", none: "other",
};
const CATEGORY_JA: Record<ModerationCategory, string> = {
  sexual: "性的な内容", hate: "差別・ひどい暴言", threat: "脅し", personal_info: "個人情報", none: "その他",
};

/** 対戦の舞台は、開いている店から選ぶ（要件#102: コンビニは準備中の間は使わない） */
function pickStage(): StageId {
  const open = openStages();
  const list = open.length > 0 ? open : [...STAGES];
  return list[Math.floor(Math.random() * list.length)];
}
