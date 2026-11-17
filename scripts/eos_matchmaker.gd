extends Node
## Epic Online Services（EOS）で対戦相手を探すための入り口（要件#32）。
##
## ★ まだ動かない骨組み。EOS を使うには、依頼者が次を用意する必要がある（docs/EOS.md）:
##   1. Epic Games 開発者ポータルの登録と、プロダクト（Product ID / Sandbox ID / Deployment ID / Client ID / Client Secret）
##   2. EOS SDK（開発者ポータルにログインして入手。再配布は不可）
##   3. Godot 用の EOS プラグイン（GDExtension）を addons/ に入れる
## 作業環境からは Epic のサイトとプラグインの配布元に接続できず、関数名を確かめられなかったため、
## EOS を実際に呼ぶ部分は書いていない（推測で書くと、動かないコードを残すことになるため）。
##
## 役割の分け方（決めたこと）:
##   - EOS: 相手を探す（ロビー）・フレンド招待・Epic のアカウント
##   - ゲームサーバー: 対戦の進行・AIの判定・レーティング（改ざんできないようにサーバーに置く）
## 流れ:
##   ホスト側: EOS でロビーを作る（属性: game=cushara, lang, format, rating）
##             → ゲームサーバーに room_create（eos_lobby=ロビーID）→ 返ってきた部屋コードをロビーの属性 room に書く
##   参加側:   EOS でロビーを探す（lang・format が同じ、rating が近い）→ 入る → 属性 room を読んで room_join
##   ランクマッチを EOS で組む場合は room_create に ranked=true を付ける（サーバーの ALLOW_RANKED_ROOMS=1 が必要。
##   ただし、EOS のロビーをサーバー側で確かめる仕組み（EOS の Web API）を足すまでは有効にしないこと）。

signal status(text: String)
## 相手が見つかって、ゲームサーバーの部屋コードが決まった（versus_game.gd が room_join / 待機に使う）
signal room_ready(code: String, is_host: bool)
signal failed(message: String)


## EOS のプラグインが入っているか（入っていなければ versus_game.gd はゲームサーバーのマッチングを使う）
func available() -> bool:
	return Engine.has_singleton("IEOS") or ClassDB.class_exists("EOSGRuntime")


## ランダムマッチ（レーティングが近い相手）を EOS のロビーで探す
func find_match(_lang: String, _format: String, _rating: int) -> void:
	failed.emit(tr("EOS はまだ設定されていません。ゲームサーバーのマッチングを使います"))


## フレンドを招待する（Epic のオーバーレイ）
func invite_friend(_room_code: String) -> void:
	failed.emit(tr("EOS はまだ設定されていません。部屋コードを友達に伝えてください"))


func cancel() -> void:
	pass
