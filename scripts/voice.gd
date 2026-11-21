extends Node
## 音声対戦の録音と再生。押している間だけ録音する（プッシュ・トゥ・トーク）。
## 送る形式: 16kHz・モノラル・8bit μ-law（G.711）を base64 にしたもの（1秒あたり約21KB）。サーバーの server/src/audio.ts と同じ。

signal auto_stopped                # 最大の長さに達して録音が止まった
signal level_changed(level: float) # 録音中の音量（0〜1）

const RATE: int = 16000
const MAX_SECONDS: float = 20.0
const BUS: String = "VoiceMic"

var _capture: AudioEffectCapture = null
var _mic: AudioStreamPlayer = null
var _out: AudioStreamPlayer = null
var _recording: bool = false
var _samples: PackedFloat32Array = PackedFloat32Array()
var _src_rate: float = 44100.0


func _ready() -> void:
	_out = AudioStreamPlayer.new()
	add_child(_out)


## マイクが使える状態か（設定でオフ、または入力機器が無い場合は false）
func available() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return false
	return AudioServer.get_input_device_list().size() > 0


func _ensure_mic() -> bool:
	if _capture != null:
		return true
	if not available():
		return false
	var idx: int = AudioServer.get_bus_index(BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
		AudioServer.set_bus_mute(idx, true)   # 自分の声をスピーカーから出さない
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = BUS
	add_child(_mic)
	_mic.play()
	_src_rate = AudioServer.get_mix_rate()
	return _capture != null


func is_recording() -> bool:
	return _recording


func start_recording() -> bool:
	if _recording or not _ensure_mic():
		return false
	_capture.clear_buffer()
	_samples = PackedFloat32Array()
	_recording = true
	return true


## 録音を止めて、送る形のデータ（μ-law のバイト列）を返す。短すぎるときは空
func stop_recording() -> PackedByteArray:
	if not _recording:
		return PackedByteArray()
	_pull()
	_recording = false
	level_changed.emit(0.0)
	if _samples.size() < int(_src_rate * 0.25):
		return PackedByteArray()
	# 上限（20秒）を少しでも超えるとサーバーに断られるので、少し手前で切る
	var cap: int = int(_src_rate * (MAX_SECONDS - 0.1))
	if _samples.size() > cap:
		_samples = _samples.slice(0, cap)
	return encode_mulaw(_resample(_samples, _src_rate, float(RATE)))


## マイクを閉じる（対戦が終わったら。レビュー2-9: 終わってもマイクが開いたままだった）。次に録音するときにまた開く
func release_mic() -> void:
	cancel_recording()
	if _mic != null and is_instance_valid(_mic):
		_mic.stop()
		_mic.queue_free()
	_mic = null
	_capture = null


func cancel_recording() -> void:
	_recording = false
	_samples = PackedFloat32Array()
	level_changed.emit(0.0)


func _process(_delta: float) -> void:
	if not _recording:
		return
	var level: float = _pull()
	level_changed.emit(level)
	if float(_samples.size()) >= _src_rate * MAX_SECONDS:
		auto_stopped.emit()


## マイクのバッファを取り出してためる。戻り値は今回分の音量
func _pull() -> float:
	if _capture == null:
		return 0.0
	var n: int = _capture.get_frames_available()
	if n <= 0:
		return 0.0
	var frames: PackedVector2Array = _capture.get_buffer(n)
	var peak: float = 0.0
	for f in frames:
		var m: float = (f.x + f.y) * 0.5
		_samples.append(m)
		peak = maxf(peak, absf(m))
	return clampf(peak * 1.5, 0.0, 1.0)


# ---------------------------------------------------------------- 変換

static func _resample(src: PackedFloat32Array, from_rate: float, to_rate: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if src.is_empty():
		return out
	var ratio: float = from_rate / to_rate
	var count: int = int(float(src.size()) / ratio)
	out.resize(count)
	for i in range(count):
		# 区間の平均（簡易ローパス）
		var start: int = int(float(i) * ratio)
		var end_i: int = mini(src.size(), maxi(start + 1, int(float(i + 1) * ratio)))
		var sum: float = 0.0
		for j in range(start, end_i):
			sum += src[j]
		out[i] = sum / float(end_i - start)
	return out


static func encode_mulaw(samples: PackedFloat32Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(samples.size())
	for i in range(samples.size()):
		var s: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		var sgn: int = 0
		if s < 0:
			sgn = 0x80
			s = -s
		s = mini(s + 0x84, 32635)
		var exponent: int = 7
		var mask: int = 0x4000
		while (s & mask) == 0 and exponent > 0:
			exponent -= 1
			mask >>= 1
		var mantissa: int = (s >> (exponent + 3)) & 0x0F
		out[i] = (~(sgn | (exponent << 4) | mantissa)) & 0xFF
	return out


static func decode_mulaw(data: PackedByteArray) -> PackedByteArray:
	# 16bit リトルエンディアンの PCM にする
	var out: PackedByteArray = PackedByteArray()
	out.resize(data.size() * 2)
	for i in range(data.size()):
		var u: int = (~data[i]) & 0xFF
		var sgn: int = u & 0x80
		var exponent: int = (u >> 4) & 0x07
		var mantissa: int = u & 0x0F
		var sample: int = ((mantissa << 3) + 0x84) << exponent
		sample -= 0x84
		if sgn != 0:
			sample = -sample
		out.encode_s16(i * 2, sample)
	return out


func play_base64(b64: String) -> float:
	var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return 0.0
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = decode_mulaw(raw)
	_out.stream = wav
	_out.volume_db = linear_to_db(maxf(GameSettings.volume, 0.0001))
	_out.play()
	return float(raw.size()) / float(RATE)


## 自動テスト用: 指定秒数の小さな音（正弦波）を μ-law で作る
static func test_tone(seconds: float) -> PackedByteArray:
	var s: PackedFloat32Array = PackedFloat32Array()
	var n: int = int(seconds * float(RATE))
	s.resize(n)
	for i in range(n):
		s[i] = sin(TAU * 220.0 * float(i) / float(RATE)) * 0.2
	return encode_mulaw(s)
