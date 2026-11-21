import html, sys
# プライバシーポリシーの HTML を作る（要件#101, #102）: python3 tools/privacy_gen.py server/public
OUT = sys.argv[1]

CSS = """body{margin:0;background:#f3eee3;color:#24212b;font:16px/1.8 "Noto Sans JP","Hiragino Sans","Yu Gothic UI","Microsoft YaHei",sans-serif}
main{max-width:820px;margin:0 auto;padding:24px 20px 60px}h1{font-size:26px;margin:8px 0}h2{font-size:19px;margin:28px 0 6px;border-bottom:2px solid #24212b;padding-bottom:4px}
h3{font-size:16px;margin:18px 0 4px;color:#d23f2f}table{border-collapse:collapse;width:100%;margin:8px 0}th,td{border:1px solid #c9c0ad;padding:6px 8px;text-align:left;vertical-align:top}
th{background:#e7e0d2}.box{background:#fffdf6;border-left:4px solid #d23f2f;padding:10px 14px;margin:12px 0}.muted{color:#6b6574;font-size:14px}nav a{margin-right:12px}.ph{background:#ffd23f;padding:0 4px}"""

def page(lang, title, nav, body):
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{html.escape(title)}</title><style>{CSS}</style></head>
<body><main><nav>{nav}</nav>{body}</main></body></html>
"""

NAV = '<a href="/privacy?lang=ja">日本語</a><a href="/privacy?lang=en">English</a><a href="/privacy?lang=zh">中文</a><a href="/privacy?lang=ko">한국어</a>'

JA = """<h1>カスハラ防衛線 プライバシーポリシー</h1>
<p class="muted">制定日: 2026年11月19日　／　運営者: medal　／　お問い合わせ: <span class="ph">【連絡先メールアドレス】</span></p>
<p>「カスハラ防衛線」（以下「本ゲーム」）の運営者（以下「運営」）は、本ゲームで扱う利用者の情報を、このポリシーのとおりに取り扱います。</p>

<h2>1. 扱う情報</h2>
<table><tr><th>情報</th><th>使う目的</th><th>保存する場所・期間</th></tr>
<tr><td>アカウント: ランダムに作るID、フロアネーム（名前）、ログイン用の合言葉（サーバーには元に戻せない形で保存）、レーティング・勝敗、称号・名札の飾り・対戦用キャラクター、作成日時・最後に接続した日時</td><td>ログイン、対戦の相手探し、ランキング、対戦相手への表示</td><td>ゲームサーバー。退職（アカウントの削除）まで</td></tr>
<tr><td>対戦での発言（文字・声を文字に起こしたもの）</td><td>対戦の進行、不適切な内容のチェック、AIによる採点（3節）</td><td>3節のとおり</td></tr>
<tr><td>声（声の対戦）</td><td>相手に届けること、文字に起こすこと</td><td>保存しません</td></tr>
<tr><td>1人用モードでの返事</td><td>AIによる採点（ゲームサーバーのAIを使う設定のとき）</td><td>お客さん1人分の会話の間だけサーバーのメモリに置き、最長30分で消します。保存しません</td></tr>
<tr><td>通報（通報した人・された人・理由・メモ・試合のID）、自動で見つかった不適切な発言の一部</td><td>迷惑行為への対応</td><td>ゲームサーバー。1年で自動で消します</td></tr>
<tr><td>利用停止・警告の記録、対戦の同意の記録（同意した版と日時）</td><td>規約違反への対応、同意の確認</td><td>ゲームサーバー。退職まで</td></tr>
<tr><td>接続元のIPアドレス</td><td>アカウントの大量作成・接続の乱用の防止、同じ回線どうしのランクマッチの防止</td><td>サーバーのメモリで一時的に使い、データベースには保存しません</td></tr>
<tr><td>このパソコンの中の記録（設定・ハイスコア・称号・ショップの持ち物など）</td><td>ゲームを遊ぶため</td><td>利用者のパソコンの中だけ。運営には送りません（自分のAPIキーは、このパソコン用に暗号化して保存します）</td></tr>
</table>

<h2>2. 外部への送信（外部のサービス）</h2>
<table><tr><th>送り先</th><th>送るもの</th><th>目的</th></tr>
<tr><td>AIの事業者（Anthropic, PBC〔米国〕。運営の設定により、他のOpenAI互換のAI事業者）</td><td>採点・チェックする発言の文字、お客さんの設定、会話の流れ</td><td>採点、不適切な内容のチェック、お客さんのセリフづくり</td></tr>
<tr><td>文字起こしのサービス（運営が設定したもの）</td><td>声の対戦での声</td><td>声を文字に起こすため</td></tr>
<tr><td>Epic Games, Inc.〔米国〕（Epic Online Services）</td><td>Epicアカウント、またはこのパソコン用の匿名のID、対戦相手探しの情報、声（ボイスチャット）、実績</td><td>対戦相手探し、フレンド招待、声の中継、実績</td></tr>
<tr><td>Cloudflare, Inc.〔米国〕</td><td>ゲームサーバーとの通信（暗号化されています）</td><td>ゲームサーバーへの通信の経路</td></tr>
<tr><td>Microsoft Corporation〔米国〕</td><td>（Microsoft Store での配信・購入に関する情報。本ゲームから送るものはありません）</td><td>配信</td></tr>
</table>
<p>各社での取り扱いは、それぞれのプライバシーポリシーによります。外国にある事業者に送るため、送り先の国の個人情報の保護の制度のもとで扱われます。</p>

<h2>3. 対戦での発言の取り扱い（同意をいただく内容）</h2>
<div class="box">オンライン対戦での発言は、ユーザーどうしの通信です。運営は、次の扱いについて、初めて対戦するときに、ゲームの画面で内容を示し、利用者から個別に明確な同意（チェックと「同意して対戦へ進む」）をいただいたうえで行います。同意しない場合は対戦できませんが、1人用モードは遊べます。同意は、ゲームの「設定」からいつでも取り消せます（取り消すと対戦できなくなります）。</div>
<ol>
<li><b>発言のチェックと判定</b>: 対戦での発言（文字・声）は、不適切な内容（性的な内容・差別・脅し・個人情報）のチェックと、AIによる採点に使います。</li>
<li><b>外部のAIへの送信</b>: チェックと採点のため、発言の文字（声は文字に起こしたもの）を、ゲームサーバーからAIの事業者（Anthropic など、運営が設定した事業者）に送ります。声の対戦では、文字に起こすために声を文字起こしのサービスに送ります。</li>
<li><b>相手への中継</b>: 発言は対戦相手に届けます。声は Epic Online Services（Epic Games）のボイスチャットで、話している間そのまま相手に聞こえます（チェックは文字に起こしてから行うため、声そのものは止められません）。Epic が使えないときはゲームサーバーを通し、チェックを通った声だけを届けます。</li>
<li><b>保存</b>: 発言は、試合中と試合の終わりから1時間だけ、サーバーのメモリに置きます。通報（相手からの通報、または自動の不適切発言の検出）があった試合だけ、会話の文字を30日保存し、運営が通報の確認に使います。声そのものは保存しません。</li>
<li><b>不適切な発言</b>: 見つかった発言は（文字は）相手に見せず、発言した人に警告します。3回で負けになり、自動で通報されます。</li>
</ol>
<p>同意の内容を変えるときは、もう一度同意をいただきます。</p>

<h2>4. 運営が会話を見るとき</h2>
<p>運営が保存された会話を見るのは、通報への対応のときだけです。見た記録は運営の管理用の記録に残ります。管理用の画面は、サーバーの外からは開けない作りにしています。</p>

<h2>5. 安全のための対策</h2>
<p>通信の暗号化、ログイン用の合言葉の元に戻せない形での保存、APIキーなどの秘密の値の分離、管理用の画面への外部からの接続の遮断、保存期間を過ぎた情報の自動の削除を行います。</p>

<h2>6. 削除・開示などのご請求</h2>
<p>ゲームの「設定」→「退職する（データ削除）」で、このパソコンの記録と、ゲームサーバーのアカウント（名前・レート・称号・同意の記録など）を消せます。ただし、迷惑行為への対応のため、あなたへの通報の記録（1年）と、通報された試合の会話（30日）は、保存期間が過ぎるまで残ります。あなたがした通報は、だれがしたかを消して残ります。対戦の結果の記録は、相手のレーティングの計算のため、名前のない形で残ります。サーバーにつながらないときや、開示・訂正・利用停止などのご請求は、上の連絡先へご連絡ください。</p>

<h2>7. 未成年の方へ</h2>
<p>未成年の方は、保護者の方の同意を得てからご利用ください。</p>

<h2>8. このポリシーの変更</h2>
<p>このポリシーを変えるときは、このページとゲームのお知らせでお知らせします。3節の内容を変えるときは、あらためて同意をいただきます。</p>
"""

EN = """<h1>Kasuhara Defense Line – Calm the Angry Customer — Privacy Policy</h1>
<p class="muted">Effective: November 19, 2026 / Operator: medal / Contact: <span class="ph">[Contact email]</span></p>
<p>The operator of "Kasuhara Defense Line – Calm the Angry Customer" (the "Game") handles users' information as described in this policy. If this translation differs from the Japanese version, the Japanese version prevails.</p>

<h2>1. Information we handle</h2>
<table><tr><th>Information</th><th>Purpose</th><th>Where / how long</th></tr>
<tr><td>Account: a random ID, floor name, a login token (stored on the server in a non-reversible form), rating and record, titles, name-tag decorations, versus character, created and last-seen times</td><td>Login, matchmaking, rankings, showing you to opponents</td><td>Game server, until you resign (delete your account)</td></tr>
<tr><td>What you say in versus matches (text, and voice transcribed to text)</td><td>Running the match, checking for inappropriate content, AI scoring (section 3)</td><td>See section 3</td></tr>
<tr><td>Voice (voice matches)</td><td>Delivering it to your opponent, transcription</td><td>Not stored</td></tr>
<tr><td>Your replies in solo mode</td><td>AI scoring (when the game server's AI is used)</td><td>Kept in server memory only during one customer's conversation, deleted within 30 minutes; not stored</td></tr>
<tr><td>Reports (reporter, reported player, reason, note, match ID) and excerpts of automatically detected inappropriate remarks</td><td>Handling misconduct</td><td>Game server; deleted automatically after 1 year</td></tr>
<tr><td>Records of suspensions and warnings; your versus consent (version and time)</td><td>Enforcing the rules; confirming consent</td><td>Game server, until you resign</td></tr>
<tr><td>Your IP address</td><td>Preventing mass account creation and connection abuse; preventing ranked matches on the same network</td><td>Used temporarily in server memory; not stored in the database</td></tr>
<tr><td>Data on your PC (settings, high scores, titles, shop items, etc.)</td><td>Playing the game</td><td>Only on your PC; not sent to the operator (your own API key is stored encrypted for your PC)</td></tr>
</table>

<h2>2. Sending to external services</h2>
<table><tr><th>Recipient</th><th>What</th><th>Purpose</th></tr>
<tr><td>AI provider (Anthropic, PBC, USA; or another OpenAI-compatible provider set by the operator)</td><td>Text of remarks being scored/checked, customer settings, conversation context</td><td>Scoring, checking inappropriate content, writing customer lines</td></tr>
<tr><td>Speech-to-text service (set by the operator)</td><td>Your voice in voice matches</td><td>Transcription</td></tr>
<tr><td>Epic Games, Inc., USA (Epic Online Services)</td><td>Your Epic account or an anonymous ID for your PC, matchmaking data, voice (voice chat), achievements</td><td>Matchmaking, friend invites, voice delivery, achievements</td></tr>
<tr><td>Cloudflare, Inc., USA</td><td>Encrypted traffic to the game server</td><td>Network route to the game server</td></tr>
<tr><td>Microsoft Corporation, USA</td><td>(Distribution/purchase information through Microsoft Store; the Game itself sends nothing)</td><td>Distribution</td></tr>
</table>
<p>Each company handles data under its own privacy policy. Because recipients are located abroad, data is handled under the personal-information protection system of their countries.</p>

<h2>3. How remarks in versus matches are handled (what you consent to)</h2>
<div class="box">Remarks in online versus matches are communications between users. The first time you play versus, the Game shows the details below and asks for your specific, explicit consent (ticking a box and pressing "Agree and continue to versus"). Without consent you cannot play versus, but solo mode remains available. You can withdraw consent at any time in Settings (you won't be able to play versus after withdrawing).</div>
<ol>
<li><b>Checking and scoring</b>: What you say in versus matches (text and voice) is checked for inappropriate content (sexual content, discrimination, threats, personal information) and scored by AI.</li>
<li><b>Sending to external AI</b>: For checking and scoring, the text of what you say (voice is transcribed first) is sent from the game server to an AI provider chosen by the operator (such as Anthropic). In voice matches, your voice is sent to a speech-to-text service.</li>
<li><b>Delivery to your opponent</b>: What you say is delivered to your opponent. Through Epic Online Services (Epic Games) voice chat, your voice is heard live while you talk (checks run after transcription, so the voice itself can't be stopped). When Epic isn't available, voice goes through the game server and only voice that passes the check is delivered.</li>
<li><b>Storage</b>: Remarks are kept in server memory only during the match and for 1 hour after it ends. Only for reported matches (reported by your opponent or by automatic detection) is the conversation text stored for 30 days, for the operator to review the report. Voice itself is never stored.</li>
<li><b>Inappropriate remarks</b>: Detected remarks are hidden from your opponent (as text) and the speaker receives a warning. Three warnings mean a loss, and the match is reported automatically.</li>
</ol>
<p>If these terms change, we will ask for your consent again.</p>

<h2>4. When the operator views conversations</h2>
<p>The operator views stored conversations only to handle reports. Each viewing is recorded in the operator's admin log. The admin screen cannot be opened from outside the server.</p>

<h2>5. Security</h2>
<p>We encrypt traffic, store login tokens in a non-reversible form, keep secrets such as API keys separate, block outside access to the admin screen, and delete data automatically when its retention period ends.</p>

<h2>6. Deletion and other requests</h2>
<p>In Settings → "Resign (delete data)", you can delete the data on your PC and your game-server account (name, rating, titles, consent record and so on). However, to deal with abuse, reports made against you (1 year) and the conversations of reported matches (30 days) are kept until their retention period ends. Reports you made are kept with your identity removed. Match results are kept without names so opponents' ratings stay correct. If the server is unreachable, or for requests to disclose, correct or stop using your data, contact us at the address above.</p>

<h2>7. Minors</h2>
<p>If you are a minor, please obtain consent from a parent or guardian before using the Game.</p>

<h2>8. Changes</h2>
<p>We will announce changes to this policy on this page and through in-game news. Changes to section 3 require your consent again.</p>
"""

ZH = """<h1>《顾客骚扰防线 – 安抚愤怒的顾客》隐私政策</h1>
<p class="muted">制定日期：2026年11月19日 ／ 运营方：medal ／ 联系方式：<span class="ph">【联系邮箱】</span></p>
<p>《顾客骚扰防线 – 安抚愤怒的顾客》（以下称“本游戏”）的运营方按照本政策处理用户信息。若本译文与日文版有出入，以日文版为准。</p>

<h2>1. 处理的信息</h2>
<table><tr><th>信息</th><th>用途</th><th>保存位置与期限</th></tr>
<tr><td>账号：随机生成的ID、楼层名（名字）、登录凭证（以不可还原的形式保存在服务器）、等级分与胜负、称号、名牌装饰、对战角色、创建与最后连接时间</td><td>登录、匹配对手、排行榜、向对手显示</td><td>游戏服务器，保存至离职（删除账号）</td></tr>
<tr><td>对战中的发言（文字，以及语音转成的文字）</td><td>进行比赛、检查不当内容、AI评分（第3节）</td><td>见第3节</td></tr>
<tr><td>语音（语音对战）</td><td>传达给对手、转成文字</td><td>不保存</td></tr>
<tr><td>单人模式中的回复</td><td>AI评分（使用游戏服务器的AI时）</td><td>仅在与一位顾客对话期间保存在服务器内存中，最长30分钟后删除；不保存</td></tr>
<tr><td>举报（举报人、被举报人、理由、备注、比赛ID）及自动检测到的不当发言片段</td><td>处理不当行为</td><td>游戏服务器，1年后自动删除</td></tr>
<tr><td>停用与警告记录、对战同意记录（版本与时间）</td><td>处理违规行为、确认同意</td><td>游戏服务器，保存至离职</td></tr>
<tr><td>连接来源IP地址</td><td>防止大量创建账号和滥用连接、防止同一网络的玩家进行排位赛</td><td>仅在服务器内存中临时使用，不保存到数据库</td></tr>
<tr><td>电脑中的记录（设置、最高分、称号、商店物品等）</td><td>游玩本游戏</td><td>仅保存在用户的电脑中，不发送给运营方（自己的API密钥会针对此电脑加密保存）</td></tr>
</table>

<h2>2. 发送给外部服务</h2>
<table><tr><th>接收方</th><th>发送内容</th><th>目的</th></tr>
<tr><td>AI服务商（Anthropic, PBC〔美国〕；或运营方设定的其他兼容OpenAI的服务商）</td><td>需评分和检查的发言文字、顾客设定、对话上下文</td><td>评分、检查不当内容、生成顾客台词</td></tr>
<tr><td>语音转文字服务（运营方设定）</td><td>语音对战中的语音</td><td>转成文字</td></tr>
<tr><td>Epic Games, Inc.〔美国〕（Epic Online Services）</td><td>Epic账号或此电脑的匿名ID、匹配信息、语音（语音聊天）、成就</td><td>匹配对手、好友邀请、传达语音、成就</td></tr>
<tr><td>Cloudflare, Inc.〔美国〕</td><td>与游戏服务器的通信（已加密）</td><td>连接游戏服务器的通信路径</td></tr>
<tr><td>Microsoft Corporation〔美国〕</td><td>（与 Microsoft Store 发行和购买相关的信息；本游戏本身不发送任何内容）</td><td>发行</td></tr>
</table>
<p>各公司按照其各自的隐私政策处理数据。由于接收方位于境外，数据将在接收方所在国家的个人信息保护制度下处理。</p>

<h2>3. 对战发言的处理（需要你同意的内容）</h2>
<div class="box">在线对战中的发言属于用户之间的通信。首次对战时，本游戏会在画面上展示以下内容，并请你给予具体、明确的同意（勾选并按下“同意并进入对战”）。不同意则无法对战，但可以玩单人模式。你可以随时在“设置”中撤回同意（撤回后将无法对战）。</div>
<ol>
<li><b>发言的检查与判定</b>：对战中的发言（文字和语音）会用于检查不当内容（色情内容、歧视、威胁、个人信息）以及由AI评分。</li>
<li><b>发送给外部AI</b>：为了检查和评分，游戏服务器会把发言的文字（语音会先转成文字）发送给运营方设定的AI服务商（如 Anthropic）。语音对战中，会把语音发送给语音转文字服务。</li>
<li><b>传达给对手</b>：发言会传达给对战对手。通过 Epic Online Services（Epic Games）的语音聊天时，说话的声音会直接被对手听到（检查是在转成文字之后进行，因此无法拦截声音本身）。无法使用 Epic 时，经由游戏服务器，只传达通过检查的语音。</li>
<li><b>保存</b>：发言只在比赛中以及比赛结束后1小时内保存在服务器内存中。只有被举报的比赛（对手举报或自动检测到不当发言），对话文字才会保存30天，供运营方核实举报。语音本身不会保存。</li>
<li><b>不当发言</b>：检测到的发言（文字）不会显示给对手，并警告发言者。3次警告判负，并自动举报。</li>
</ol>
<p>上述内容变更时，会再次请你同意。</p>

<h2>4. 运营方查看对话的情形</h2>
<p>运营方仅在处理举报时查看保存的对话。每次查看都会记录在运营方的管理记录中。管理画面无法从服务器外部打开。</p>

<h2>5. 安全措施</h2>
<p>我们对通信加密，以不可还原的形式保存登录凭证，分开保管API密钥等机密信息，阻止外部连接管理画面，并在保存期限届满后自动删除信息。</p>

<h2>6. 删除与其他请求</h2>
<p>在游戏的“设置”→“离职（删除数据）”中，可以删除电脑中的记录以及游戏服务器上的账号（名字、等级分、称号、同意记录等）。但为了处理骚扰行为，针对你的举报记录（1年）和被举报比赛的对话（30天）会保留到保存期限结束。你提交的举报会在删除提交者身份后保留。为了计算对手的等级分，比赛结果会以不含名字的形式保留。无法连接服务器时，或需要申请查阅、更正、停止使用等，请通过上方联系方式联系我们。</p>

<h2>7. 未成年人</h2>
<p>未成年人请在征得监护人同意后使用本游戏。</p>

<h2>8. 本政策的变更</h2>
<p>本政策变更时，会在本页面和游戏内通知中公布。第3节的内容变更时，会再次征求你的同意。</p>
"""

KO = """<h1>카스하라 방어선 – 화난 손님 달래기 개인정보 처리방침</h1>
<p class="muted">제정일: 2026년 11월 19일 ／ 운영자: medal ／ 문의: <span class="ph">[연락처 이메일 주소]</span></p>
<p>「카스하라 방어선 – 화난 손님 달래기」(이하 「본 게임」)의 운영자(이하 「운영」)는 본 게임에서 다루는 이용자의 정보를 이 방침에 따라 취급합니다. 이 번역과 일본어판의 내용이 다를 경우 일본어판이 우선합니다.</p>

<h2>1. 다루는 정보</h2>
<table><tr><th>정보</th><th>이용 목적</th><th>보관 장소·기간</th></tr>
<tr><td>계정: 무작위로 만드는 ID, 플로어 네임(이름), 로그인용 암호(서버에는 원래대로 되돌릴 수 없는 형태로 저장), 레이팅·승패, 칭호·명찰 장식·대전용 캐릭터, 생성 일시·마지막 접속 일시</td><td>로그인, 대전 상대 찾기, 랭킹, 대전 상대에게 표시</td><td>게임 서버. 퇴직(계정 삭제)까지</td></tr>
<tr><td>대전에서의 발언(글자·음성을 글자로 변환한 것)</td><td>대전 진행, 부적절한 내용 확인, AI 채점(3절)</td><td>3절과 같음</td></tr>
<tr><td>음성(음성 대전)</td><td>상대에게 전달, 글자로 변환</td><td>저장하지 않습니다</td></tr>
<tr><td>1인 플레이 모드의 답변</td><td>AI 채점(게임 서버의 AI를 쓰는 설정일 때)</td><td>손님 1명분의 대화 동안만 서버 메모리에 두고, 최장 30분 안에 지웁니다. 저장하지 않습니다</td></tr>
<tr><td>신고(신고한 사람·신고된 사람·이유·메모·경기 ID), 자동으로 발견된 부적절한 발언의 일부</td><td>민폐 행위 대응</td><td>게임 서버. 1년 후 자동 삭제</td></tr>
<tr><td>이용 정지·경고 기록, 대전 동의 기록(동의한 버전과 일시)</td><td>규약 위반 대응, 동의 확인</td><td>게임 서버. 퇴직까지</td></tr>
<tr><td>접속한 IP 주소</td><td>계정 대량 생성·접속 남용 방지, 같은 회선끼리의 랭크 매치 방지</td><td>서버 메모리에서 일시적으로만 쓰고, 데이터베이스에는 저장하지 않습니다</td></tr>
<tr><td>이 PC 안의 기록(설정·하이스코어·칭호·상점 소지품 등)</td><td>게임을 즐기기 위해</td><td>이용자의 PC 안에만. 운영에 보내지 않습니다(내 API 키는 이 PC용으로 암호화해 저장합니다)</td></tr>
</table>

<h2>2. 외부로의 전송(외부 서비스)</h2>
<table><tr><th>받는 곳</th><th>보내는 것</th><th>목적</th></tr>
<tr><td>AI 사업자(Anthropic, PBC〔미국〕. 운영 설정에 따라 다른 OpenAI 호환 AI 사업자)</td><td>채점·확인할 발언의 글자, 손님 설정, 대화의 흐름</td><td>채점, 부적절한 내용 확인, 손님 대사 생성</td></tr>
<tr><td>음성 인식 서비스(운영이 설정한 것)</td><td>음성 대전의 음성</td><td>음성을 글자로 바꾸기 위해</td></tr>
<tr><td>Epic Games, Inc.〔미국〕(Epic Online Services)</td><td>Epic 계정 또는 이 PC용 익명 ID, 대전 상대 찾기 정보, 음성(보이스 채팅), 업적</td><td>대전 상대 찾기, 친구 초대, 음성 중계, 업적</td></tr>
<tr><td>Cloudflare, Inc.〔미국〕</td><td>게임 서버와의 통신(암호화되어 있습니다)</td><td>게임 서버로 가는 통신 경로</td></tr>
<tr><td>Microsoft Corporation〔미국〕</td><td>(Microsoft Store에서의 배포·구입에 관한 정보. 본 게임에서 보내는 것은 없습니다)</td><td>배포</td></tr>
</table>
<p>각 회사에서의 취급은 각 회사의 개인정보 처리방침에 따릅니다. 외국에 있는 사업자에게 보내므로, 받는 나라의 개인정보 보호 제도 아래에서 취급됩니다.</p>

<h2>3. 대전 발언의 취급(동의를 받는 내용)</h2>
<div class="box">온라인 대전에서의 발언은 이용자끼리의 통신입니다. 운영은 다음 취급에 대해, 처음 대전할 때 게임 화면에서 내용을 보여 주고 이용자에게 개별적이고 명확한 동의(체크와 「동의하고 대전으로」)를 받은 뒤에 행합니다. 동의하지 않으면 대전은 할 수 없지만 1인 플레이 모드는 즐길 수 있습니다. 동의는 게임의 「설정」에서 언제든 철회할 수 있습니다(철회하면 대전을 할 수 없게 됩니다).</div>
<ol>
<li><b>발언의 확인과 판정</b>: 대전에서의 발언(글자·음성)은 부적절한 내용(성적인 내용·차별·협박·개인정보) 확인과 AI 채점에 씁니다.</li>
<li><b>외부 AI로의 전송</b>: 확인과 채점을 위해 발언의 글자(음성은 글자로 변환한 것)를 게임 서버에서 AI 사업자(Anthropic 등 운영이 설정한 사업자)에게 보냅니다. 음성 대전에서는 글자로 바꾸기 위해 음성을 음성 인식 서비스에 보냅니다.</li>
<li><b>상대에게 중계</b>: 발언은 대전 상대에게 전달됩니다. Epic Online Services(Epic Games)의 보이스 채팅에서는 말하는 동안 목소리가 그대로 상대에게 들립니다(확인은 글자로 바꾼 뒤에 하므로 목소리 자체는 막을 수 없습니다). Epic을 쓸 수 없을 때는 게임 서버를 통해 확인을 통과한 음성만 전달합니다.</li>
<li><b>보관</b>: 발언은 경기 중과 경기가 끝난 뒤 1시간 동안만 서버 메모리에 둡니다. 신고(상대의 신고 또는 부적절한 발언의 자동 검출)가 있었던 경기만 대화의 글자를 30일간 보관하고, 운영이 신고 확인에 씁니다. 음성 자체는 저장하지 않습니다.</li>
<li><b>부적절한 발언</b>: 발견된 발언은 (글자로는) 상대에게 보이지 않게 하고, 발언한 사람에게 경고합니다. 3번이면 패배가 되고 자동으로 신고됩니다.</li>
</ol>
<p>동의 내용을 바꿀 때는 다시 동의를 받습니다.</p>

<h2>4. 운영이 대화를 보는 경우</h2>
<p>운영이 보관된 대화를 보는 것은 신고에 대응할 때뿐입니다. 열람 기록은 운영의 관리용 기록에 남습니다. 관리용 화면은 서버 밖에서는 열 수 없게 만들어져 있습니다.</p>

<h2>5. 안전을 위한 대책</h2>
<p>통신 암호화, 로그인용 암호를 되돌릴 수 없는 형태로 저장, API 키 등 비밀 값의 분리, 관리용 화면에 대한 외부 접속 차단, 보관 기간이 지난 정보의 자동 삭제를 합니다.</p>

<h2>6. 삭제·열람 등의 청구</h2>
<p>게임의 「설정」→「퇴직 (데이터 삭제)」에서 이 PC의 기록과 게임 서버의 계정(이름·레이팅·칭호·동의 기록 등)을 지울 수 있습니다. 다만 민폐 행위 대응을 위해, 당신에 대한 신고 기록(1년)과 신고된 경기의 대화(30일)는 보관 기간이 끝날 때까지 남습니다. 당신이 한 신고는 누가 했는지를 지운 채 남습니다. 대전 결과 기록은 상대의 레이팅 계산을 위해 이름이 없는 형태로 남습니다. 서버에 연결할 수 없을 때나 열람·정정·이용 정지 등의 청구는 위 연락처로 연락해 주세요.</p>

<h2>7. 미성년자에게</h2>
<p>미성년자는 보호자의 동의를 받은 뒤 이용해 주세요.</p>

<h2>8. 이 방침의 변경</h2>
<p>이 방침을 바꿀 때는 이 페이지와 게임 공지로 알립니다. 3절의 내용을 바꿀 때는 다시 동의를 받습니다.</p>
"""

for lang, title, body in (("ja", "プライバシーポリシー | カスハラ防衛線", JA), ("en", "Privacy Policy | Kasuhara Defense Line – Calm the Angry Customer", EN), ("zh", "隐私政策 | 顾客骚扰防线 – 安抚愤怒的顾客", ZH), ("ko", "개인정보 처리방침 | 카스하라 방어선 – 화난 손님 달래기", KO)):
    open(f"{OUT}/privacy.{lang}.html", "w", encoding="utf-8").write(page(lang, title, NAV, body))
print("ok")
