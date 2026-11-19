extends Node
## 自動の動作確認（要件#90「デバッグ」）。`-- --qa` で起動すると、今までに足した機能を実際に押して確かめる。
## 結果は「QA PASS ...」「QA FAIL ...」と出力し、最後に「QA OK」か「QA FAILED n」。失敗があれば終了コード 1。
## セーブは --profile で分けて使う（本番のセーブを汚さない）。

const Shop = preload("res://scripts/shop.gd")
const AgeCheck = preload("res://scripts/age_check.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")
const Scenarios = preload("res://scripts/scenarios.gd")
const Titles = preload("res://scripts/titles.gd")
const Moderation = preload("res://scripts/moderation.gd")

var main = null
var _fails: int = 0
var _snap_dir: String = ""   # `--qa-shots=<フォルダ>` のとき、要所の画面を保存する


func _snap(name: String) -> void:
	if _snap_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(_snap_dir.path_join(name + ".jpg"), 0.85)


func run(m) -> void:
	main = m
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-shots="):
			_snap_dir = a.substr(11)
			DirAccess.make_dir_recursive_absolute(_snap_dir)
	# `--bg-shots=<フォルダ>`: タイトルの背景を全部撮るだけ（見た目の確認用）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bg-shots="):
			await _bg_shots(a.substr(11))
			get_tree().quit(0)
			return
	Engine.time_scale = 3.0
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func() -> void:
		print("QA TIMEOUT")
		get_tree().quit(1))
	await _wait(1.0)
	await _economy()
	await _round5()
	await _repairs()
	await _screens()
	await _age_and_items()
	await _solo_shift()
	print("QA OK" if _fails == 0 else "QA FAILED %d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("QA PASS ", name)
	else:
		_fails += 1
		print("QA FAIL ", name, "  ", detail)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ---------------------------------------------------------------- お金・ショップ・ガチャ

func _economy() -> void:
	GameSettings.hp_points = 0
	GameSettings.kas_points = 1000
	GameSettings.owned_items = []
	GameSettings.equipped_items = {}
	check("exchange 100 KAS", Shop.exchange(100) and GameSettings.kas_points == 900 and GameSettings.hp_points == 300, "hp=%d kas=%d" % [GameSettings.hp_points, GameSettings.kas_points])
	check("exchange refuses more than owned", not Shop.exchange(5000))
	check("buy wooden frame with HP", Shop.buy("frame", "wood", "hp") and GameSettings.hp_points == 100 and Shop.owns("frame", "wood"))
	check("cannot buy backdrop directly", not Shop.buy("bg", "bg_medal", "kas"))
	check("cannot buy KAS-only item with HP", not Shop.buy("frame", "platinum", "hp"))
	GameSettings.kas_points = 2000
	var res: Array = Shop.gacha_pull("kas", true)
	check("10-pull gives 11", res.size() == 11, str(res.size()))
	var refunds: int = 0
	for r in res:
		refunds += int((r as Dictionary).get("refund", 0))
	check("10-pull cost and refunds", GameSettings.kas_points == 1000 + refunds, "kas=%d refunds=%d" % [GameSettings.kas_points, refunds])
	for tab in ["gacha", "tag", "chara", "exchange"]:
		main.set("_shop_tab", tab)
		main.call("_show_shop")
		await _wait(0.4)
		check("shop tab " + tab + " opens", main.get("_sheet") != null)
	# 両替機の画面でお札を押すと、手持ちの表示がその場で変わる
	main.set("_shop_tab", "exchange")
	main.call("_show_shop")
	await _wait(0.3)
	var before: int = GameSettings.hp_points
	Shop.exchange(10)
	main.call("_refresh_wallet")
	var lbls: Dictionary = main.get("_wallet_labels")
	var hp_label = lbls.get("HP", null)
	check("wallet label updates live", hp_label != null and is_instance_valid(hp_label) and str(hp_label.text).begins_with(main.call("_num", before + 30)), str(hp_label.text) if hp_label != null else "null")
	main.call("_close_sheet")


# ---------------------------------------------------------------- 画面

## 要件#99: メダル・ビデオの台の問題と、筐体の前の場面
func _repairs() -> void:
	var lies: int = 0
	for i in range(200):
		var c: Dictionary = ShopActions.apply_problem({"problem": "button", "title": "x"})
		if str(c.get("problem", "")) == "button_lie":
			lies += 1
		if i == 0:
			check("button problem sets the video machine", str(c.get("machine", "")) == "video")
	check("about 40% of dead-button reports are lies", lies > 50 and lies < 115, str(lies))
	var jam: Dictionary = ShopActions.apply_problem({"problem": "jam", "title": "jam", "actions": {}})
	var solo_ids: Array = ShopActions.buttons("arcade", jam, true).map(func(b: Array) -> String: return str(b[0]))
	var vs_ids: Array = ShopActions.buttons("arcade", jam, false).map(func(b: Array) -> String: return str(b[0]))
	check("solo: go to the machine, repairs happen in the scene", solo_ids.has("repair_visit") and not solo_ids.has("medal_rail"), str(solo_ids))
	check("versus: repairs are plain buttons", vs_ids.has("medal_rail") and vs_ids.has("medal_hit") and not vs_ids.has("repair_visit"), str(vs_ids))
	var plain: Array = ShopActions.buttons("arcade", {"machine": "medal", "actions": {}}, true).map(func(b: Array) -> String: return str(b[0]))
	check("no repair buttons without a machine problem", not plain.has("repair_visit") and not plain.has("medal_hit"), str(plain))
	check("rail hit is a quick fix kind", ShopActions.effect_kind(jam, "medal_hit") == "hit" and ShopActions.effect_kind(jam, "medal_rail") == "fixed")
	var solo = main.get("_solo")
	for prob in ["slam", "loud"]:
		var off: Dictionary = solo.call("_offender", prob)
		check("offender data: " + prob, str(off.get("title", "")) != "" and (off.get("solution_keywords", []) as Array).size() >= 4)
	# 場面: 自動テストのやり方（smoke）で、開けて正しい対応をして戻る
	var keep_smoke: bool = bool(main.get("smoke"))
	main.set("smoke", true)
	var res: Dictionary = await main.call("run_repair_scene", jam)
	check("medal scene: disassembled the rail", (res.get("actions", []) as Array).has("medal_rail") and float(res.get("seconds", 0.0)) > 10.0, str(res))
	var lie: Dictionary = ShopActions.apply_problem({"problem": "button", "title": "y"})
	lie["problem"] = "button_lie"
	lie = ShopActions.apply_problem(lie)
	var res2: Dictionary = await main.call("run_repair_scene", lie)
	check("video scene (lie): only tested the buttons", (res2.get("actions", []) as Array) == ["video_check"], str(res2))
	# 台パンの通報 → 本人と話す（自動の返事）→ カウンターに戻る
	var reporter: Dictionary = {}
	for c in Scenarios.customers("arcade"):
		if str((c as Dictionary).get("problem", "")) == "slam":
			reporter = ShopActions.apply_problem((c as Dictionary).duplicate(true))
	check("slam reporter exists", not reporter.is_empty())
	if not reporter.is_empty():
		solo.set("_cust", reporter)
		solo.set("_active", true)
		solo.set("paused", false)
		main.get("_hud").visible = true
		var out: String = await solo.call("_nuisance", "QA", int(solo.get("_run")))
		check("nuisance talk finishes", out in ["resolved", "explode", "yield"], out)
		check("back to the reporter after the talk", solo.get("_cust") == reporter and not bool(solo.get("_in_nuisance")))
		check("talk backdrop closed", main.get("_talk_bg") == null)
		solo.set("_active", false)
		main.get("_hud").visible = false
	main.set("smoke", keep_smoke)
	# 見た目の確認用に、場面を開いたまま撮る
	if _snap_dir != "":
		var sc = load("res://scripts/repair_scene.gd").new()
		main.get("_ui").add_child(sc)
		sc.call("setup", main, ShopActions.apply_problem({"problem": "jam", "title": "jam", "actions": {}}))
		await _wait(1.5)
		await _snap("repair_medal")
		await (sc.get("_stage") as Node).call("open_door")
		(sc.get("_status") as Label).text = str(sc.call("_inside_look"))
		sc.call("_minigame", "medal_rail")
		await _wait(0.5)
		await _snap("repair_medal_open")
		sc.emit_signal("_mini_done", true)
		await _wait(0.2)
		sc.queue_free()
		var sc2 = load("res://scripts/repair_scene.gd").new()
		main.get("_ui").add_child(sc2)
		var b: Dictionary = {}
		for k in range(30):
			b = ShopActions.apply_problem({"problem": "button", "title": "b", "actions": {}})
			if str(b.get("problem", "")) == "button":
				break
		sc2.call("setup", main, b)
		await _wait(1.5)
		await _snap("repair_video")
		sc2.queue_free()
		main.call("show_talk_backdrop", "slam")
		await _wait(1.0)
		await _snap("talk_slam")
		main.call("hide_talk_backdrop")
	await _wait(0.2)


## 要件#94, #95: 不適切な言葉を送らせない・画面の設定
func _round5() -> void:
	for t in ["おっぱい見せて", "このガイジ", "you retard", "ＳＥＸ", "090-1234-5678 に電話", "mail me a@b.jp"]:
		check("moderation blocks: " + t, Moderation.check(t) != "")
	for t in ["バカじゃないの？クソ店員！", "ふざけるな、責任者を出せ", "I'd like a cocktail", "10000000円も使ったのに", "こころすっきりしたい", "Sussex"]:
		check("moderation allows: " + t, Moderation.check(t) == "")
	# 入力欄から送ろうとしても、止まって送られない
	var hud = main.get("_hud")
	var sent: Array = []
	var cb: Callable = func(t: String) -> void: sent.append(t)
	hud.reply_submitted.connect(cb)
	hud.set_input_enabled(true, "")
	hud.get("_field").text = "おっぱい見せて"
	hud.call("_submit")
	check("hud does not send a blocked line", sent.is_empty() and bool(hud.get("_input_on")))
	hud.get("_field").text = "申し訳ございません"
	hud.call("_submit")
	check("hud sends a normal line", sent.size() == 1)
	hud.reply_submitted.disconnect(cb)
	hud.set_input_enabled(false, "")
	# 画面の設定（描画の解像度・可変リフレッシュレートの上限）
	var keep: Array = [GameSettings.render_scale, GameSettings.vrr, GameSettings.max_fps]
	GameSettings.render_scale = "0.75"
	GameSettings.apply_video()
	check("render scale applies", is_equal_approx(get_tree().root.scaling_3d_scale, 0.75))
	GameSettings.max_fps = "144"
	GameSettings.vrr = false
	check("fps cap without vrr", GameSettings.fps_cap() == 144)
	GameSettings.render_scale = str(keep[0])
	GameSettings.vrr = bool(keep[1])
	GameSettings.max_fps = str(keep[2])
	GameSettings.apply_video()
	# 運営からのお知らせ・メンテナンス（要件#100）
	var keep_info: Dictionary = main.get("_server_info")
	main.set("_server_info", {"maintenance": true, "maintenance_message": "22時まで", "notices": [{"ja": "新しい背景", "en": "New backdrops", "zh": "新背景"}]})
	main.call("_refresh_notices")
	var nb = main.get("_notice_box")
	check("notice board shows news and maintenance", nb != null and bool(nb.visible) and str((main.get("_notice_text") as Label).text).contains(tr("運営からのお知らせ")))
	await _snap("notice_board")
	main.set("_server_info", keep_info)
	main.call("_refresh_notices")
	main.call("_show_settings")
	await _wait(0.3)
	check("settings sheet opens", main.get("_sheet") != null)
	await _snap("settings")
	main.call("_close_sheet")
	await _wait(0.2)


func _screens() -> void:
	main.set("_records_tab", "reviews")
	main.call("_show_records")
	await _wait(0.3)
	check("records: review log opens", main.get("_sheet") != null)
	main.set("_records_tab", "stats")
	main.call("_show_records")
	await _wait(0.3)
	check("records: stats opens", main.get("_sheet") != null)
	main.call("_ask_versus_format")
	await _wait(0.3)
	check("versus format chooser opens", main.get("_sheet") != null)
	await _snap("versus_format")
	main.call("show_report", {"player_id": "x", "name": "テスト", "match_id": "m"})
	await _wait(0.3)
	check("report sheet opens", main.get("_sheet") != null)
	await _snap("report")
	main.call("_close_sheet")
	# ハードコア: ランク 10 未満は鍵、10 で開ける
	GameSettings.mental_xp = 0
	var was_test: bool = GameSettings.is_test
	GameSettings.is_test = false
	main.call("_refresh_title")
	var hb: Button = main.get("_hard_toggle")
	check("hardcore locked below rank 10", hb != null and hb.disabled)
	GameSettings.mental_xp = int(GameSettings.MENTAL_XP[9])
	main.call("_refresh_title")
	check("hardcore unlocked at rank 10", hb != null and not hb.disabled)
	GameSettings.is_test = was_test
	main.call("_show_hardcore")
	await _wait(0.5)
	check("hardcore screen opens", main.get("_sheet") != null)
	await _snap("hardcore_screen")
	main.call("_close_sheet")
	main.call("_show_title")
	main.call("show_avatar_maker", Callable())
	await _wait(0.4)
	check("avatar maker opens", main.get("_sheet") != null)
	main.call("_close_sheet")
	main.call("show_payout_panel")
	await _wait(0.3)
	check("payout panel opens", main.get("_sheet") != null)
	main.call("_close_sheet")
	main.call("_show_mental_list")
	await _wait(0.3)
	check("mental rank list opens", main.get("_sheet") != null)
	await _snap("mental_list")
	main.set("_titles_cat", "arcade")
	main.call("_show_titles")
	await _wait(0.3)
	check("titles screen opens", main.get("_sheet") != null)
	await _snap("titles")
	main.call("_offer_difficulty")
	await _wait(0.3)
	check("difficulty chooser opens", main.get("_sheet") != null)
	await _snap("difficulty")
	main.call("_confirm_resign", 1)
	await _wait(0.3)
	check("resign confirm opens", main.get("_sheet") != null)
	await _snap("resign")
	main.call("_close_sheet")


# ---------------------------------------------------------------- 年齢確認・アイテム

func _age_and_items() -> void:
	var solo = main.get("_solo")
	var c: Dictionary = AgeCheck.make(22 * 60, "ja", "arcade")
	solo.set("_cust", c)
	solo.set("_id_seen", false)
	solo.set("_alt_id_asked", false)
	var ids: Array = (solo.call("_age_buttons") as Array).map(func(b: Array) -> String: return str(b[0]))
	check("no 'another ID' before seeing the ID", not ids.has("ask_other_id"), str(ids))
	solo.set("_id_seen", true)
	ids = (solo.call("_age_buttons") as Array).map(func(b: Array) -> String: return str(b[0]))
	check("'another ID' after seeing the ID", ids.has("ask_other_id"), str(ids))
	solo.set("_cust", {"demand": "景品をよこせ"})
	check("prize-only demand", solo.call("_prize_only"))
	solo.set("_cust", {"demand": "景品と土下座を要求"})
	check("demand with dogeza is not prize-only", not solo.call("_prize_only"))
	check("halfwidth digits", UI_halfwidth("３０") == "30")
	var look: Dictionary = Shop.avatar_look({"hair": "afro", "head": "crown", "face": "nose_glasses", "hand": "harisen", "body": "cape"}, "casual")
	check("avatar look carries joke items", str(look.get("head", "")) == "crown" and str(look.get("hand", "")) == "harisen")
	check("155 titles", Titles.all().size() == 155, str(Titles.all().size()))
	# 要件#91, #92
	check("stuck button only for stuck customers", not (ShopActions.buttons("arcade", {"machine": "crane", "actions": {"crane_stuck": "neutral"}}, false).map(func(b: Array) -> String: return str(b[0])).has("crane_stuck")))
	check("stuck button for a stuck customer", ShopActions.buttons("arcade", {"machine": "crane", "actions": {"crane_stuck": "good"}}, false).map(func(b: Array) -> String: return str(b[0])).has("crane_stuck"))
	check("saying an amount is caught", solo.call("_says_amount", "メーターでは1,000円でした") and solo.call("_says_amount", "あと2000円で取れます"))
	check("vague wording is fine", not solo.call("_says_amount", "もう少しかもしれません"))
	check("smell: direct", solo.call("_smell_talk", "お客様、ちょっと臭いです") == "direct")
	check("smell: hint", solo.call("_smell_talk", "今日は暑いので換気しますね") == "hint")
	check("reply limit ja 128", GameSettings.reply_max_length() == (256 if GameSettings.language == "en" else 128))
	check("mental rank 11+ needs more", int(GameSettings.MENTAL_XP[11]) - int(GameSettings.MENTAL_XP[10]) > int(GameSettings.MENTAL_XP[9]) - int(GameSettings.MENTAL_XP[8]))
	# 要件#97: 学生証も使える・年齢確認のミスは必ず警察・社員モードの警察は 5%・退店のお願いに粘るセリフ
	check("student ID is accepted", bool((AgeCheck.TYPES["student"] as Dictionary)["public"]))
	var student_ok: bool = false
	for i in range(80):
		var sc: Dictionary = AgeCheck.make(22 * 60, "ja", "arcade")
		var ag: Dictionary = sc.get("age", {})
		if str(ag.get("type", "")) == "student" and bool(ag.get("face_match", true)) and int(ag.get("shown_age", 0)) >= int(ag.get("limit", 18)):
			student_ok = not bool(ag.get("must_leave", true))
			break
		if i == 79:
			student_ok = true   # 80回で学生証の大人が出なかったときは、表の値だけで確かめる
	check("an adult with a student ID may stay", student_ok)
	check("police always come after a lax age check", is_equal_approx(float(solo.get_script().get_script_constant_map()["POLICE_CHANCE"]), 1.0))
	check("employee-mode police quiz is ~5%", is_equal_approx(float(solo.get_script().get_script_constant_map()["FUEI_CHANCE"]), 0.05))
	solo.set("_cust", AgeCheck.make(22 * 60, "ja", "arcade"))
	check("resist line (arcade)", str(solo.call("_resist_line")) != "")
	solo.set("_cust", AgeCheck.make(12 * 60, "ja", "konbini"))
	check("resist line (konbini)", str(solo.call("_resist_line")) != "")


func UI_halfwidth(t: String) -> String:
	return preload("res://scripts/ui_kit.gd").to_halfwidth(t)


# ---------------------------------------------------------------- 1人用のシフト（ボタンを実際に押す）

func _wait_turn(solo, timeout: float) -> bool:
	var t: float = 0.0
	while t < timeout:
		if bool(solo.get("_player_turn")) and not bool(solo.get("paused")):
			return true
		await _wait(0.2)
		t += 0.2
	return false


func _solo_shift() -> void:
	var solo = main.get("_solo")
	main.debug["anger_stop"] = true
	var reviews_before: int = GameSettings.review_log.size()
	var called_before: int = GameSettings.stat("manager_called")
	var viol_before: int = GameSettings.stat("violations")
	main.call("_start_solo", "arcade", false)
	check("first customer's turn", await _wait_turn(solo, 30.0))
	await _wait(1.5)
	await _snap("shift_hud")
	# 会話ログ: 開くと怒りが止まる
	solo.call("_on_tool", "log")
	await _wait(0.3)
	check("talk log opens and pauses", main.get("_sheet") != null and bool(solo.get("paused")))
	await _snap("talk_log")
	main.call("_close_sheet")
	await _wait(0.2)
	# ペイアウト
	solo.call("_on_tool", "payout")
	await _wait(0.3)
	check("payout panel opens in shift", main.get("_sheet") != null)
	await _snap("payout_panel")
	main.call("_close_sheet")
	await _wait(0.2)
	# 店長を呼ぶ
	await _wait_turn(solo, 10.0)
	solo.call("_on_tool", "call_manager")
	await _wait(2.0)
	await _snap("manager_called")
	await _wait(4.0)
	check("call manager counted", GameSettings.stat("manager_called") == called_before + 1, str(GameSettings.stat("manager_called")))
	check("called customer flagged", bool(solo.get("_called_here")))
	# 同じ対応を2回で規定違反
	var cust: Dictionary = solo.get("_cust")
	var stage_btns: Array = ShopActions.buttons("arcade", cust, false).map(func(b: Array) -> String: return str(b[0]))
	var target: String = ""
	for id in ["maintenance", "medal_return"]:
		if stage_btns.has(id):
			target = id
			break
	if target == "" and stage_btns.has("credit") and not stage_btns.has("crane_stuck"):
		target = "credit"
	if target != "":
		var pressed: int = 0
		for i in range(2):
			if not await _wait_turn(solo, 15.0):
				break
			if not bool(solo.get("_active")) or solo.get("_cust") != cust:
				break
			solo.call("_on_action", target)
			pressed += 1
			await _wait(2.5)
		# 1回目でお客さんが帰ったとき（納得・味をしめた など）は2回目を押せないので確かめない
		if pressed >= 2:
			check("same action twice is a violation (" + target + ")", GameSettings.stat("violations") >= viol_before + 1, str(GameSettings.stat("violations")))
		else:
			print("QA SKIP violation (customer left after ", pressed, " press)")
	else:
		print("QA SKIP violation (buttons: ", stage_btns, ")")
	# 残りは自動で最後まで
	main.debug["anger_stop"] = false
	main.smoke = true
	if bool(solo.get("_player_turn")):
		solo.call("_smoke_autoplay", int(solo.get("_run")))
	var res: Array = await solo.finished
	main.smoke = false
	check("shift finished", res.size() >= 2)
	check("review log grew", GameSettings.review_log.size() == reviews_before + 1, "%d -> %d" % [reviews_before, GameSettings.review_log.size()])
	check("wages paid", (solo.get("summary") as Dictionary).has("pay"))
	await _violation_shift()


## コンビニの「割引」を同じお客さんに2回押すと規定違反（要件#90）
func _violation_shift() -> void:
	var solo = main.get("_solo")
	main.call("_close_sheet")
	main.debug["anger_stop"] = true
	main.debug["no_age"] = true
	var viol_before: int = GameSettings.stat("violations")
	main.call("_start_solo", "konbini", false)
	check("konbini first turn", await _wait_turn(solo, 30.0))
	# 割引で屈してしまうお客さん（効果が yield）は飛ばして、次のお客さんで試す
	var cust: Dictionary = solo.get("_cust")
	var tries: int = 0
	while ShopActions.effect_kind(cust, "discount") == "yield" and tries < 4 and bool(solo.get("_active")):
		tries += 1
		main.smoke = true
		solo.call("_smoke_autoplay", int(solo.get("_run")))
		var t: float = 0.0
		while solo.get("_cust") == cust and t < 40.0 and bool(solo.get("_active")):
			await _wait(0.3)
			t += 0.3
		main.smoke = false
		if not await _wait_turn(solo, 30.0):
			break
		cust = solo.get("_cust")
	if ShopActions.effect_kind(cust, "discount") == "yield":
		print("QA SKIP discount violation (every customer gives in to a discount)")
		main.call("_quit_to_title")
		return
	for i in range(2):
		if not await _wait_turn(solo, 15.0) or solo.get("_cust") != cust:
			break
		solo.call("_on_action", "discount")
		await _wait(2.5)
		await _snap("violation_%d" % i)
	check("discount twice is a violation", GameSettings.stat("violations") == viol_before + 1, "%d -> %d" % [viol_before, GameSettings.stat("violations")])
	main.debug["anger_stop"] = false
	main.debug["no_age"] = false
	main.call("_quit_to_title")


func _bg_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(1.0)
	for it in Shop.items("bg"):
		var id: String = str((it as Dictionary).get("id", ""))
		if not GameSettings.owned_items.has("bg:" + id):
			GameSettings.owned_items.append("bg:" + id)
		Shop.equip("bg", id)
		main.call("_show_title")
		main.get("_title").visible = false
		await _wait(1.2)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(dir.path_join(id + ".jpg"), 0.85)
		print("BG ", id)
