# Epic Online Services（EOS）でのマッチング（要件#32）

## 結論
- **EOS は無料**。Epic Games Store で売らなくても、Steam・Microsoft Store 版でも使える（Epic Games 開発者ポータルへの登録は必要）。
- このゲームでは **EOS は「相手を探す・フレンドを招待する」だけ**に使い、**対戦の進行・AIの判定・レーティングは今のゲームサーバー**で行う。
  - 理由: AIの判定はAPIキーを持つサーバーでしかできない。レーティングをプレイヤーのPCやP2Pで決めると改ざんできる。
- **今の状態**: ゲームサーバー側の受け口（EOS で組んだ部屋）と、ゲーム側の入り口（`scripts/eos_matchmaker.gd`）の骨組みまで。
  EOS を実際に呼ぶ部分は**未実装**。作業環境から Epic のサイトとプラグインの配布元に接続できず、SDK の入手にも依頼者の Epic アカウントが要るため。
  EOS が入っていないあいだ、対戦は今までどおりゲームサーバーのマッチング（ランクマッチ・部屋コードのフレンド対戦）で動く。

## 依頼者がすること
1. https://dev.epicgames.com/portal で組織とプロダクトを作る。
2. プロダクトの「Product Settings」で次を控える: Product ID / Sandbox ID / Deployment ID / Client ID / Client Secret（クライアントの種類は「GameClient」）。
3. 「Epic Account Services」は、Epic のアカウントでログインさせたい場合だけ設定する。使わない場合は「Device ID」でのログイン（EOS Connect）でよい（Steam 版は Steam のアカウントで EOS Connect にログインする方法もある）。
4. EOS SDK（C SDK）を開発者ポータルからダウンロードする（再配布不可なので、リポジトリには入れない）。
5. Godot 用の EOS プラグイン（GDExtension。例: "Epic Online Services Godot"）を `addons/` に入れ、SDK を指定の場所に置く。

## 実装すること（引き継ぐ人向け）
`scripts/eos_matchmaker.gd` の3つの関数を、入れたプラグインの API で書く。

| 関数 | EOS でやること |
|---|---|
| `find_match(lang, format, rating)` | ロビー検索（属性 `game=cushara`、`lang`、`format` が同じ。`rating` が近い順）。見つからなければロビーを作る（最大2人）。ロビーを作った側は、ゲームサーバーに `room_create`（`eos_lobby` 付き）を送り、返ってきた部屋コードをロビーの属性 `room` に書く。参加した側は `room` を読んで `room_join`。どちらも `room_ready(code, is_host)` を出す |
| `invite_friend(room_code)` | ロビーを作り（属性 `room`）、Epic のフレンド招待を開く。招待を受けた側は参加して `room` を読む |
| `cancel()` | ロビーから抜ける |

`scripts/versus_game.gd` の `request()` で、`eos_matchmaker.available()` が true のときに EOS を使い、`room_ready` を受けたら今の `room_join` / 待機に流す。

### ランクマッチを EOS で組む場合
ゲームサーバーの `room_create` に `ranked: true` を付けると、その部屋はランクマッチとして記録される。
ただし、**サーバーは今のところ EOS のロビーが本物かを確かめられない**ので、仲間どうしでレーティングを稼げてしまう。
そのため、サーバーの環境変数 `ALLOW_RANKED_ROOMS=1` を入れない限り使えないようにしてある（既定は無効）。
有効にする前に、サーバーで EOS の Web API（ロビーの参加者の確認）を呼ぶ処理を `server/src/lobby.ts` の `createRoom` / `joinRoom` に足すこと。

## 検討メモ
- EOS の音声チャット（RTC）も無料で、今の「押して話す」の代わりに使える。ただし、判定のための文字起こしにはゲームサーバーに声を送る必要があるので、今の方式（声をサーバー経由で中継）のままでもよい。
- EOS の「Leaderboards / Stats」でランキングを出すこともできるが、レーティングの計算はゲームサーバーに置いたままにする。
