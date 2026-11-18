extends Node
## 自動の動作確認（要件#90「デバッグ」）。`-- --qa` で起動すると、今までに足した機能を実際に押して確かめる。
## 結果は「QA PASS ...」「QA FAIL ...」と出力し、最後に「QA OK」か「QA FAILED n」。失敗があれば終了コード 1。
## セーブは --profile で分けて使う（本番のセーブを汚さない）。

const Shop = preload("res://scripts/shop.gd")
const AgeCheck = preload("res://scripts/age_check.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")
const Titles = preload("res://scripts/titles.gd")

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
