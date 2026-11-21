extends Node
## BGM（要件#36）。曲は tools/make_bgm.py で作ったオリジナル（assets/bgm/*.ogg）。
## play("konbini") で切り替え（0.8秒でクロスフェード）。set_tension(0..1) で、怒りが高いときに少し速く・高くする。

const TRACKS: Dictionary = {
	"title": "res://assets/bgm/title.ogg",
	"konbini": "res://assets/bgm/konbini.ogg",
	"arcade": "res://assets/bgm/arcade.ogg",
	"versus": "res://assets/bgm/versus.ogg",
}
const FADE: float = 0.8

var _fade: Tween = null
var _players: Array = []
var _active: int = 0
var _current: String = ""
var _tension: float = 0.0
var _duck: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(2):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func _target_db() -> float:
	return linear_to_db(maxf(GameSettings.bgm_volume * _duck, 0.0001))


func refresh_volume() -> void:
	var p: AudioStreamPlayer = _players[_active]
	if p.playing:
		p.volume_db = _target_db()


## 音声対戦で相手の声を聞きやすくするため、一時的に小さくする（1 = 元の大きさ）
func duck(amount: float) -> void:
	_duck = clampf(amount, 0.0, 1.0)
	refresh_volume()


func play(track: String) -> void:
	if track == _current or not TRACKS.has(track):
		return
	if DisplayServer.get_name() == "headless":
		_current = track
		return
	_current = track
	var stream: AudioStream = load(str(TRACKS[track]))
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var nxt: AudioStreamPlayer = _players[_active]
	nxt.stream = stream
	nxt.volume_db = -40.0
	nxt.play()
	# 前の切り替えがまだ途中なら止める（すぐ切り替えると、今鳴らす方を前の tween が止めてしまうため）
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var tw: Tween = create_tween()
	_fade = tw
	tw.set_parallel(true)
	tw.tween_property(nxt, "volume_db", _target_db(), FADE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)


func stop() -> void:
	_current = ""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	# 止めるフェードも _fade で持つ（要件#109: 止めてすぐ play すると、古いフェードが新しい曲を止めていた）
	var tw: Tween = create_tween().set_parallel(true)
	_fade = tw
	var playing: Array = []
	for p in _players:
		var pl: AudioStreamPlayer = p
		if pl.playing:
			playing.append(pl)
			tw.tween_property(pl, "volume_db", -60.0, FADE)
	if playing.is_empty():
		tw.kill()
		return
	tw.chain().tween_callback(func() -> void:
		for pl2 in playing:
			(pl2 as AudioStreamPlayer).stop())


## 0..1。怒りが高いと少しだけ速く（高く）なる
func set_tension(t: float) -> void:
	# フレームの速さに関係なく同じ速さで近づける（要件#109: 144Hz などで速すぎた）
	var k: float = 1.0 - exp(-3.0 * get_process_delta_time())
	_tension = lerpf(_tension, clampf(t, 0.0, 1.0), k)
	var p: AudioStreamPlayer = _players[_active]
	p.pitch_scale = 1.0 + 0.06 * _tension
