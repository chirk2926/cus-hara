# Microsoft Store の掲載に使うもの（要件#100, #102）

パートナーセンター（https://partner.microsoft.com/dashboard）で入力するものの下書きです。〔〕の中は依頼者が決めて書きかえてください。
ストア用の画像は CI が描いた `docs/store/`（1920×1080、日本語・英語・中国語・韓国語）を使います。
**コンビニは今「準備中」で閉じています（要件#102）。** コンビニを閉じたまま出すなら、紹介文の「コンビニ」の部分を消すか「近日公開」にしてください（管理画面の 設定 → 運営 → 「コンビニを開ける」で開けられます）。パッケージ（MSIX）は CI の成果物 `CusHara-msix`（docs/MAINTENANCE.md 7節）。

## 1. 基本の情報
| 項目 | 入れるもの |
|---|---|
| 発行者の表示名 | medal（著作権表示は © 2026 medal game corner） |
| アプリ名（予約） | カスハラ防衛線 ／ 英語: Kasuhara Defense Line – Calm the Angry Customer ／ 中国語: 顾客骚扰防线 – 安抚愤怒的顾客 ／ 韓国語: 카스하라 방어선 – 화난 손님 달래기 |
| カテゴリ | ゲーム → シミュレーション（サブ: カジュアル・パーティ） |
| 価格 | 790円（予定。ゲーム内の購入はなし。ゲーム内の通貨 HP・CUS はゲームの中だけのもので、お金では買えない） |
| アプリ内購入 | なし |
| プライバシーポリシーの URL | `https://game.mgc-sv.com/privacy`（英語は `?lang=en`、中国語は `?lang=zh`、韓国語は `?lang=ko`。ゲームサーバーが配る） |
| サポートの連絡先 | support@mgc-sv.com |
| Web サイト | https://cus.mgc-sv.com/ |
| 必要なもの | Windows 10 / 11（64ビット）、キーボード。マイクは声の対戦のときだけ |
| 機能の宣言（Capabilities） | インターネット（クライアント）、マイク（声の対戦） |
| 年齢 | 下の 4 節の答えで IARC が決める |

## 2. 紹介文

### 日本語
**短い説明（1行）**
理不尽なクレームに、言葉で立ち向かえ。AIのお客さんと口げんかしない接客ゲーム。

**説明**
コンビニとゲームセンターで働く新人スタッフになって、次々にやってくる「ちょっと理不尽なお客さん」に、自分の言葉で対応するゲームです。
返事はキーボードで自由に入力。AIがお客さんを演じ、あなたの言葉づかい・共感・解決策を採点します。謝ってばかりでも、言いなりになってもダメ。店の決まりを守りながら、納得して帰ってもらいましょう。

- AIが演じる、毎回ちがうお客さん（ネタ枠・世間話・トイレの場所を聞くだけの人も）
- 年齢確認、両替機、メダルの詰まり、台パンする客… ありそうなトラブルに、店の行動で対応
- クレーンゲームの台の調整、メダルゲームの筐体の修理などのミニゲーム
- オンライン対戦: 店員役とお客さん役に分かれて、文字か声で言い合う（ランクマッチ・フレンド対戦）
- 155個の称号、メンタルランク、背景ガチャ、キャラクターの着せかえ（ゲーム内のポイントだけ。お金はかかりません）
- 日本語・英語・中国語（簡体字）・韓国語

※ 対戦の発言は、不適切な内容のチェックとAIの判定に使います（初めての対戦の前に確認します）。

**キーワード**（7つまで）: 接客, カスハラ, クレーム, AI, 会話, タイピング, 対戦

### English
**Short description**
Talk your way through unreasonable complaints. A customer-service game where an AI plays the customer.

**Description**
You're the new clerk at a convenience store and an arcade. One after another, slightly unreasonable customers walk up to the counter, and you deal with them in your own words.
Type any reply you like. An AI plays the customer and scores your wording, empathy and solutions. Apologizing nonstop won't work, and neither will caving in. Stick to the store's rules and send them home satisfied.

- AI-played customers that are different every time (absurd ones, chatty ones, people who just want the restroom)
- Age checks, change machines, jammed medal machines, cabinet slammers: handle realistic trouble with store actions
- Mini-games: adjust crane machines, open up and repair medal-game cabinets
- Online versus: one plays the clerk, one plays the customer, arguing by text or voice (ranked and friend matches)
- 155 titles, mental rank, backdrop gacha and character dress-up (in-game points only, no real money)
- Japanese, English, Simplified Chinese and Korean

Note: remarks in versus matches are checked for inappropriate content and scored by AI (you'll be asked before your first match).

**Keywords**: customer service, complaints, AI, conversation, typing, versus, simulation

### 中文（简体）
**简短说明**
用语言应对无理的投诉。由AI扮演顾客的接待游戏。

**说明**
你是便利店和游戏厅的新店员。一个又一个“有点无理”的顾客来到柜台，你需要用自己的话来应对。
回复可以用键盘自由输入。AI扮演顾客，为你的措辞、共情和解决方案打分。一味道歉不行，言听计从也不行。遵守店里的规定，让顾客满意地离开吧。

- 由AI扮演、每次都不同的顾客（搞笑的、爱闲聊的、只想问厕所在哪的）
- 年龄确认、兑币机、推币机卡币、拍机台的客人……用店里的行动应对真实的麻烦
- 小游戏：调整抓娃娃机、打开并修理推币机
- 在线对战：一人扮演店员、一人扮演顾客，用文字或语音对决（排位赛、好友对战）
- 155个称号、心理等级、背景扭蛋、角色换装（只用游戏内点数，无需真实货币）
- 日语、英语、简体中文、韩语

注：对战中的发言会用于检查不当内容和AI评分（首次对战前会请你确认）。

**关键词**: 接待, 投诉, AI, 对话, 打字, 对战, 模拟

### 한국어
**짧은 설명**
무리한 클레임에 말로 맞서라. AI가 손님을 연기하는 접객 게임.

**설명**
편의점과 게임센터에서 일하는 신입 직원이 되어, 차례차례 찾아오는 "조금 무리한 손님"을 자신의 말로 응대하는 게임입니다.
답변은 키보드로 자유롭게 입력. AI가 손님을 연기하고, 당신의 말투·공감·해결책을 채점합니다. 사과만 해도, 시키는 대로 다 해도 안 됩니다. 가게 규칙을 지키면서 손님이 납득하고 돌아가게 하세요.

- AI가 연기하는, 매번 다른 손님 (개그 손님·수다쟁이·화장실 위치만 묻는 사람도)
- 연령 확인, 환전기, 메달 걸림, 기계를 치는 손님… 있을 법한 문제에 가게 행동으로 대응
- 인형뽑기 기계 조정, 메달 게임기 수리 등의 미니게임
- 온라인 대전: 직원 역과 손님 역으로 나뉘어 글자나 목소리로 언쟁 (랭크 매치·친구 대전)
- 칭호 155개, 멘탈 랭크, 배경 뽑기, 캐릭터 꾸미기 (게임 내 포인트만. 현금은 들지 않습니다)
- 일본어·영어·중국어(간체)·한국어

※ 대전의 발언은 부적절한 내용 확인과 AI 채점에 사용됩니다 (첫 대전 전에 확인합니다).

**키워드**: 접객, 클레임, AI, 대화, 타자, 대전, 시뮬레이션

## 3. 画像
| 種類 | 大きさ | ファイル |
|---|---|---|
| スクリーンショット（必須・1枚以上、最大10枚） | 1920×1080 | `docs/store/<言語>_NN_*.jpg`（CI がコミットに `[shots]` のときに描く。1言語8枚） |
| ストアのロゴ（アイコン） | 1:1（300×300 以上） | `packaging/msix/Assets/`（StoreLogo） |
| 宣伝用の画像（任意） | 1920×1080 など | スクリーンショットのタイトル画面を流用できる |

## 4. 年齢レーティング（IARC）の質問への答えの案
パートナーセンターの「年齢区分」で IARC の質問に答えます。下は、いまの中身に合わせた答えの案です（最後は依頼者が確かめて入力）。

| 質問の内容 | 答えの案 | 理由 |
|---|---|---|
| アプリの種類 | ゲーム | |
| 暴力 | なし（または「マンガ的な表現」） | 「台パン」「ブチギレ」は怒りの表現だけで、人を傷つける描写はない |
| 血・残虐な表現 | なし | |
| 性的な内容・ヌード | なし | AIには性的な表現を禁じ、対戦の発言はチェックして伏せる |
| 言葉づかい（暴言） | あり（軽い） | お客さんが「ふざけるな」「バカ」程度の言葉で怒る。差別語・強い暴言は出さない／止める |
| 差別・ヘイト | なし | |
| 薬物・アルコール・たばこ | あり（言及のみ） | コンビニの年齢確認で、お酒・たばこを買おうとするお客さんが出る（使う描写はない） |
| ギャンブル（本物のお金） | なし | |
| ギャンブルを模したもの | なし（※） | メダルゲームの台・スロットの見た目はあるが、賭けて遊ぶ場面はない。メダルは換金も景品交換もできない（ゲーム内でも明記） |
| ゲーム内の購入（本物のお金） | なし | ガチャは、ゲーム内のポイント（HP・CUS）だけ。お金では買えない |
| ランダムなアイテム（ガチャ） | あり（ゲーム内のポイントのみ） | 背景ガチャ。本物のお金は使わない |
| ユーザーどうしの交流 | あり | オンライン対戦で、文字・声でやりとりする。不適切な発言の自動チェック・通報・利用停止がある |
| 位置情報の共有 | なし | |
| 個人情報の共有 | なし | 名前（フロアネーム）だけを相手に表示。電話番号などは送れないようにしている |
| 制限のないインターネットへのアクセス | なし | ゲームサーバーと Epic Online Services にだけつなぐ |
| 怖い表現 | なし | |

※ IARC の質問の言い回しは変わることがあります。迷ったら、より厳しい方（「あり」）に答えると、却下されにくくなります。

## 5. 審査に出す前の確認
- [ ] パッケージの Identity（`MSIX_IDENTITY_NAME`・`MSIX_PUBLISHER`）を、パートナーセンターの「製品 ID」の値にした（GitHub の Variables。docs/MAINTENANCE.md 7節）
- [x] プライバシーポリシーの連絡先を support@mgc-sv.com に（運営者名は medal）。ゲームサーバーで公開する（`server/public/privacy.*.html`。サーバーを更新すれば出る）
- [x] ゲームの既定のサーバーの URL を https://game.mgc-sv.com にした
- [ ] EOS の開発者ポータルに、実績 t001〜t155 を登録した（docs/HANDOVER.md 4b）。本番の ID は `config/eos.local.cfg`（リポジトリに入れない）
- [ ] 審査用のメモ: 「オンライン対戦の確認には、2台で同時にランクマッチに並ぶか、フレンド対戦の部屋コードを使ってください。1人用はサーバーなしでも遊べます」
