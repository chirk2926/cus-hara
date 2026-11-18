# Epic Online Services（EOS）でのマッチング（要件#32, #48）

## 結論
- **EOS は無料**。Epic Games Store で売らなくても、Steam・Microsoft Store 版でも使える（Epic Games 開発者ポータルへの登録は必要）。
- このゲームでは **EOS は「相手を探す・フレンドを招待する」だけ**に使い、**対戦の進行・AIの判定・レーティングはゲームサーバー**で行う。
  - 理由: AIの判定はAPIキーを持つサーバーでしかできない。レーティングをプレイヤーのPCやP2Pで決めると改ざんできる。
- **今の状態（#48）**: ゲーム側（`scripts/eos_matchmaker.gd`）とサーバー側の両方を実装済み。
  - プラグイン「Epic Online Services Godot（EOSG, 3ddelano/epic-online-services-godot）」の高レベルAPI（`HPlatform` / `HAuth` / `HLobbies` / `HLobby`）を使う。
  - **作業環境ではプラグインと Epic の ID が無いため、実機での動作確認はまだ**。API の名前と引数はプラグインのソース（sample/addons 内の heos/*.gd・eos.gd）で確かめてある。
  - プラグインが入っていない、または `config/eos.cfg` の `product_id` が空のときは、EOS を使わず、今までどおりゲームサーバーのマッチング（ランクマッチ・部屋コードのフレンド対戦）で動く。

## 依頼者がすること
1. https://dev.epicgames.com/portal で組織とプロダクトを作る。
2. 「Product Settings」で次を控える: Product ID / Sandbox ID / Deployment ID / Client ID / Client Secret（クライアントのポリシーは「GameClient」。ロビー・Connect を許可）。
3. **Epic Account Services**: フレンド招待（Epic のフレンド画面）を使うなら設定する。使わない場合も、ランクマッチは「Device ID」での匿名ログイン（EOS Connect）で動く。
4. EOSG の GitHub の Releases から zip を取り、`addons/epic-online-services-godot/` をこのプロジェクトの `addons/` に置く（中の `bin/` に EOS SDK の dll が入っている）。Godot の「プロジェクト設定 → プラグイン」で有効にする（自動読み込みの HPlatform・HAuth・HLobbies などが登録される）。
5. `config/eos.cfg` をコピーして `config/eos.local.cfg` を作り、そこに 2. の値を入れる（`.gitignore` 済みなのでリポジトリには入らない。`config/eos.cfg` は空のひな形のまま）。`encryption_key` は 64 文字の16進数（自分で作る）。
   - `client_secret` は EOS の仕組み上ゲームに同梱される値で、サーバーの Claude API キーのような秘密ではない。ただし公開リポジトリに入れたくなければ、ビルドのときだけ書き込む。
6. Steam 版で Steam のアカウントを使いたい場合は、`HAuth` の Steam ログインに差し替えられる（今は Epic アカウント → 無ければ端末 ID の順）。

## 動き（scripts/eos_matchmaker.gd）

```
ensure_ready(): config/eos.cfg を読む → HPlatform.setup_eos_async(HCredentials)
               → HAuth.login_persistent_auth_async()（前回 Epic でログインしていれば）
               → だめなら HAuth.login_anonymous_async(名前)（端末 ID）
               → IEOS の「招待を承認した」シグナルにつなぐ

ランクマッチ find_match(lang, format, rating):
  HLobbies.search_by_attribute_async(game=cushara, lang, format, state=waiting)
  → 空きがあり、レート差 300 以内で一番近いロビーに join_async
       → ロビーの属性 room（ゲームサーバーの部屋コード）が書かれるまで最大 20 秒待つ → room_found(code)
  → 無ければ create_lobby_async（公開・2人）し、属性 game/lang/format/rating/state を書く
       → need_room(ranked=true) → versus_game.gd がサーバーへ room_create {ranked, eos_lobby}
       → 部屋コードが来たら set_room_code() でロビーの属性 room に書く → 相手が入ると match_found

フレンド招待 invite_friend(...):
  Epic アカウントでなければ HAuth.login_account_portal_async()（ブラウザでログイン）
  → 招待専用ロビー（InviteOnly）を作る → need_room(ranked=false)（レーティングなしの部屋）
  → EOS.UI.UIInterface.show_friends()（Epic のフレンド画面）から招待
  招待された側: lobby_invite_accepted → search_by_lobby_id_async → join_async → room を読んで room_join

試合が始まったら（match_found）ロビーを抜ける（作った側は destroy）。
```

- EOS の途中で失敗したら `failed` を出し、versus_game.gd はゲームサーバーのマッチング（ランク）または部屋コード（招待）に切り替える。
- プラグインの名前（`HLobbies`, `EOS` など）は直接書かず、`/root/HLobbies` の取得や `load("res://addons/.../eos.gd")` で実行時に使う。こうしないと、プラグインが無い環境でスクリプトがコンパイルできない。

## サーバー側（ランクの部屋のチェック）
- `room_create` に `ranked: true` を付けた部屋はランクマッチとして記録される（`ALLOW_RANKED_ROOMS`、既定 `1`）。
- サーバーは EOS のロビーが本物かを確かめられないので、仲間どうしでのレーティング稼ぎを防ぐため、参加のときに次を断る:
  - 同じ回線（同じIP）どうし → `same_network`（`ALLOW_SAME_IP_RANKED=1` で解除。テスト用）
  - レート差が `RANKED_ROOM_MAX_GAP`（既定 400）より大きい → `rating_gap`
- そのうえで、全ランクマッチ共通のチート対策（docs/SERVER.md「7. チート対策」）が効く。
- もっと固くするなら、EOS の Web API でロビーの参加者を確かめる処理を `server/src/lobby.ts` の `joinRoom` に足す。

## 実機で確かめること（引き継ぐ人向け）
1. 2台（または2アカウント）でランクマッチ → 片方がロビーを作り、もう片方が入って対戦が始まる。
2. ロビーが見つからないとき、20 秒待って `failed` → ゲームサーバーのマッチングに切り替わる。
3. フレンド招待 → 相手が承認すると自動で部屋に入る。
4. `config/eos.cfg` を空にするとボタンの表示が元に戻る（EOS を使わない）。

## 検討メモ
- EOS の音声チャット（RTC）も無料で、今の「押して話す」の代わりに使える。ただし、判定のための文字起こしにはゲームサーバーに声を送る必要があるので、今の方式（声をサーバー経由で中継）のままでもよい。
- EOS の「Leaderboards / Stats」でランキングを出すこともできるが、レーティングの計算はゲームサーバーに置いたままにする。
