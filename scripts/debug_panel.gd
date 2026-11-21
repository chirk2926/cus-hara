extends CanvasLayer
## テスト版のデバッグパネル（要件#85）。テスト用の exe（機能タグ testbuild）か `-- --test` で起動したときだけ出る。
## F12 か右上の「TEST」ボタンで開く・閉じる。セーブはテスト用の別のファイル（settings_test.cfg）なので、本番のデータは変わらない。
## ここの文言はテスト用なので日本語だけ（翻訳しない）。

const UI = preload("res://scripts/ui_kit.gd")
const Shop = preload("res://scripts/shop.gd")
const Titles = preload("res://scripts/titles.gd")

var main = null   # main.gd（型をつけない: debug などの独自の変数を使うため）
var _panel: PanelContainer = null
var _list: VBoxContainer = null
var _info: Label = null


func setup(m) -> void:
	main = m
	layer = 90
	# 画面のはしの「TEST BUILD」と開くボタン
	var mark: Button = Button.new()
	mark.text = "TEST  (F12)"
	mark.focus_mode = Control.FOCUS_NONE
	mark.add_theme_font_override("font", UI.font(UI.F_DOT))
	mark.add_theme_font_size_override("font_size", 14)
	var st: StyleBoxFlat = UI.flat_style(Color(0.85, 0.1, 0.15, 0.9), 6, 4)
	mark.add_theme_stylebox_override("normal", st)
	mark.add_theme_stylebox_override("hover", st)
	mark.add_theme_stylebox_override("pressed", st)
	mark.add_theme_color_override("font_color", Color.WHITE)
	mark.anchor_left = 0.5
	mark.anchor_right = 0.5
	mark.offset_left = -60
	mark.offset_right = 60
	mark.offset_top = 4
	mark.pressed.connect(toggle)
	add_child(mark)
	_build()
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F12:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_info()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.flat_style(Color(0.08, 0.08, 0.1, 0.95), 12, 6))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_right = -8
	_panel.offset_top = 40
	_panel.offset_bottom = -8
	add_child(_panel)
	var col: VBoxContainer = UI.vbox(6)
	_panel.add_child(col)
	var head: HBoxContainer = UI.hbox(8)
	col.add_child(head)
	head.add_child(UI.text("デバッグパネル", UI.S_LEAD, UI.POP, UI.F_SIGN))
	head.add_child(UI.spacer())
	var close: Button = _btn("閉じる", toggle)
	head.add_child(close)
	_info = UI.text("", 12, UI.PAPER_DIM, UI.F_DOT)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = UI.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_section("お金")
	_row([["+1,000 HP", func() -> void: _money(1000, 0)], ["+1,000 CUS", func() -> void: _money(0, 1000)], ["+10,000 CUS", func() -> void: _money(0, 10000)]])
	_row([["HP・CUS を 0 に", func() -> void:
		GameSettings.hp_points = 0
		GameSettings.kas_points = 0
		_saved()]])

	_section("解放・リセット")
	_row([["称号を全部", _unlock_titles], ["称号をリセット", func() -> void:
		GameSettings.unlocked_titles = []
		GameSettings.equipped_title = ""
		GameSettings.stats = {}
		_saved()]])
	_row([["ショップの品物を全部", _unlock_items], ["持ち物をリセット", func() -> void:
		GameSettings.owned_items = []
		GameSettings.equipped_items = {}
		_saved()]])

	_section("メンタルランク")
	_row([["+1 ランク", func() -> void: _mental(1)], ["MAX（20）", func() -> void: _mental(99)], ["1 に戻す", func() -> void: _mental(-99)]])
	_row([["対戦レート +100", func() -> void: _rating(100)], ["対戦レート -100", func() -> void: _rating(-100)]])

	_section("キャラクター")
	_row([["キャラ作成を開く", func() -> void:
		toggle()
		main.call("show_avatar_maker", Callable())], ["作っていない状態に戻す", func() -> void:
		GameSettings.avatar = {}
		_saved()]])

	_section("1人用のイベント（次のお客さんから）")
	for f in [["wild", "要注意人物（頭おかしい人）を毎回"], ["manager", "店長のアドバイスを毎回"], ["age", "年齢確認のお客さんを毎回（18時以降・コンビニ）"],
			["police", "ゆるい年齢確認で必ず警察"], ["smell", "においのイベントを毎回"], ["anger_stop", "怒りゲージを止める"]]:
		var key: String = str(f[0])
		var cb: CheckBox = UI.check(str(f[1]), main.call("debug_flag", key))
		cb.add_theme_color_override("font_color", UI.PAPER)
		cb.add_theme_font_size_override("font_size", 14)
		cb.toggled.connect(func(on: bool) -> void:
			main.debug[key] = on
			_refresh_info())
		_list.add_child(cb)

	# 次のお客さんの種類を選んで出す（要件#106。台本のお客さんから選ぶ。ゲームセンターのシフトで）
	_section("次のお客さんの種類（毎回）")
	var kinds: Array = [["", "ふつう（ランダム）"], ["stuck", "景品が引っかかった"], ["spend_true", "〇〇円使っても取れない（本当）"], ["spend_lie", "〇〇円使っても取れない（うそ）"],
		["jam", "メダル詰まり"], ["empty", "メダル切れ"], ["lottery", "抽選機が止まった"], ["button", "ボタンが反応しない（本当）"], ["button_lie", "ボタンが反応しない（うそ）"],
		["slam", "台パンの通報"], ["loud", "大声の通報"], ["hatmask", "年齢確認（帽子・マスク）"]]
	var ob: OptionButton = OptionButton.new()
	for i in kinds.size():
		ob.add_item(str(kinds[i][1]), i)
		if str(kinds[i][0]) == str(main.debug_kind):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void:
		main.debug_kind = str(kinds[i][0])
		_refresh_info())
	_list.add_child(ob)

	_section("1人用の判定")
	_row([["オフライン（台本）", func() -> void: _source("offline")], ["サーバー", func() -> void: _source("server")]])

	_section("画面を見る")
	_row([["客役の対戦画面", func() -> void:
		toggle()
		main.call("debug_preview_customer_view", {"gender": "m", "height": 1.05, "build": "big", "skin": "s3", "hair": "spiky", "hair_color": "black", "casual": "navy", "uniform": "green", "acc": "sunglasses"})]])
	_row([["結果のタイムカード（見本）", func() -> void:
		toggle()
		main.call("debug_preview_result")]])
	_row([["ガチャ10連（無料）", func() -> void:
		toggle()
		GameSettings.kas_points += Shop.gacha_price("kas", true)
		var res: Array = Shop.gacha_pull("kas", true)
		if res.is_empty():
			GameSettings.kas_points -= Shop.gacha_price("kas", true)
			_note("背景を全部持っているので回せません（「持ち物をリセット」で戻せます）")
			return
		main.call("_show_gacha_result", res)], ["ショップ", func() -> void:
		toggle()
		main.call("_show_shop")]])
	_row([["称号の札を出す", func() -> void:
		main.call("show_new_titles", [Titles.by_id("t001"), Titles.by_id("t150")])], ["タイトルへ戻る", func() -> void:
		toggle()
		main.call("_quit_to_title")]])

	_section("データ")
	_row([["テスト用のセーブを消す", _wipe]])


func _section(t: String) -> void:
	_list.add_child(UI.gap(4))
	_list.add_child(UI.text(t, UI.S_BODY, UI.LCD_ON, UI.F_BOLD))


func _btn(label: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _row(items: Array) -> void:
	var r: HBoxContainer = UI.hbox(4)
	_list.add_child(r)
	for it in items:
		r.add_child(_btn(str(it[0]), it[1]))


func _refresh_info() -> void:
	var flags: PackedStringArray = PackedStringArray()
	for k in main.debug:
		if bool(main.debug[k]):
			flags.append(str(k))
	if str(main.debug_kind) != "":
		flags.append("客: " + str(main.debug_kind))
	_info.text = "セーブ: %s\nサーバー: %s\n1人用の判定: %s\nHP %d / CUS %d / メンタル %d / 称号 %d\nイベント: %s" % [
		GameSettings._path(), GameSettings.server_url, GameSettings.solo_source, GameSettings.hp_points, GameSettings.kas_points,
		GameSettings.mental_rank(), GameSettings.unlocked_titles.size(), ", ".join(flags) if not flags.is_empty() else "なし"]


func _saved() -> void:
	GameSettings.save_settings()
	main.call("_refresh_title")
	_refresh_info()


func _note(t: String) -> void:
	_info.text = t


func _money(hp: int, kas: int) -> void:
	GameSettings.hp_points += hp
	GameSettings.kas_points += kas
	_saved()


func _unlock_titles() -> void:
	var ids: Array = []
	for t in Titles.all():
		ids.append(str((t as Dictionary).get("id", "")))
	GameSettings.unlocked_titles = ids
	_saved()


func _unlock_items() -> void:
	for it in Shop.data().get("items", []):
		var d: Dictionary = it
		var key: String = str(d.get("cat", "")) + ":" + str(d.get("id", ""))
		if not bool(d.get("default", false)) and not GameSettings.owned_items.has(key):
			GameSettings.owned_items.append(key)
	_saved()


func _mental(step: int) -> void:
	var r: int = clampi(GameSettings.mental_rank() + step, 1, GameSettings.MENTAL_XP.size())
	GameSettings.mental_xp = int(GameSettings.MENTAL_XP[r - 1])
	_saved()


func _rating(d: int) -> void:
	var p: Dictionary = GameSettings.last_profile.duplicate()
	p["rating"] = int(p.get("rating", 1000)) + d
	GameSettings.last_profile = p
	_saved()
	_note("（表示だけ。サーバーのレートは変わりません）")


func _source(src: String) -> void:
	GameSettings.solo_source = src
	_saved()


func _wipe() -> void:
	if GameSettings._path().find("test") < 0:
		_note("テスト用のセーブではないので消しません")
		return
	# ゲームの「退職」と同じ消し方にする（高得点・レビュー・名前・同意なども。バグチェック B-12）。接続も切る
	if main != null and main.get("api") != null:
		main.api.close_socket()
	GameSettings.wipe_all()
	_saved()
	_note("テスト用のセーブを消しました")
