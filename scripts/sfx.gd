extends Node
## 効果音をコードで合成して鳴らす（外部音声ファイル不要）

const RATE: int = 22050

var _streams: Dictionary = {}
var _players: Array = []
var _next: int = 0


func _ready() -> void:
	for i in range(6):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["talk"] = _tone([[540.0, 0.04]], 0.18, "square")
	_streams["click"] = _tone([[880.0, 0.03]], 0.25, "sine")
	_streams["send"] = _tone([[660.0, 0.05], [990.0, 0.07]], 0.3, "sine")
	_streams["good"] = _tone([[660.0, 0.08], [880.0, 0.08], [1320.0, 0.16]], 0.35, "sine")
	_streams["bad"] = _tone([[180.0, 0.12], [140.0, 0.2]], 0.35, "square")
	_streams["warn"] = _tone([[980.0, 0.07], [0.0, 0.05], [980.0, 0.07]], 0.25, "square")
	_streams["explode"] = _tone([[90.0, 0.5]], 0.6, "noise")
	_streams["win"] = _tone([[523.0, 0.1], [659.0, 0.1], [784.0, 0.1], [1047.0, 0.3]], 0.35, "sine")
	_streams["lose"] = _tone([[392.0, 0.15], [330.0, 0.15], [262.0, 0.35]], 0.35, "square")
	_streams["door"] = _tone([[1047.0, 0.18], [784.0, 0.3]], 0.3, "sine")


func _tone(notes: Array, vol: float, wave: String) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	for n in notes:
		var freq: float = float(n[0])
		var dur: float = float(n[1])
		var count: int = int(dur * RATE)
		for i in range(count):
			var t: float = float(i) / float(RATE)
			var env: float = minf(1.0, float(i) / 150.0) * minf(1.0, float(count - i) / 500.0)
			var s: float = 0.0
			if freq > 0.0:
				if wave == "square":
					s = 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
				elif wave == "noise":
					s = randf_range(-1.0, 1.0) * (1.0 - float(i) / float(count))
				else:
					s = sin(TAU * freq * t)
			var v: int = int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var st: AudioStreamWAV = AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	return st


func play(id: String, pitch: float = 1.0) -> void:
	if not _streams.has(id) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(GameSettings.volume, 0.0001))
	p.play()
