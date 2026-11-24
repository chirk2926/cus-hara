#!/usr/bin/env bash
# カスハラ防衛線: 自宅の Ubuntu / Debian サーバーに「本番」と「テスト」のゲームサーバーを作る（要件#118。docs/HOME_SERVER.md）。
# 何度流してもよい（あるものはそのまま使い、最新にそろえる）。root で流す:
#
#   sudo REPO_URL=git@github.com:<あなた>/cus-hara.git bash deploy/linux/setup.sh
#
# 作るもの:
#   本番   ユーザー cushara       /opt/cus-hara       ゲーム 127.0.0.1:8787  管理画面 127.0.0.1:8790  サービス cushara
#   テスト ユーザー cushara-test  /opt/cus-hara-test  ゲーム 127.0.0.1:8788  管理画面 127.0.0.1:8791  サービス cushara-test
# 本番とテストは、データベース・APIキー（var/secrets.json）・管理画面のパスワードがすべて別。どちらもブランチの最新で動かす。
# プログラムのファイルは root の持ち物（ゲームのサーバーからは書きかえられない）。書けるのは server/var だけ。
# 外への公開（Cloudflare Tunnel）は、ブラウザで Cloudflare にログインする手順があるので、最後に手順を出す。
set -euo pipefail

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-claude/wizardly-keller-c3rj2v}"
NODE_MAJOR=22

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die() { printf '\n\033[31mエラー: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "root で流してください（sudo bash deploy/linux/setup.sh）"
command -v apt-get >/dev/null || die "Ubuntu / Debian 用です（apt-get がありません）"

# このスクリプトのあるリポジトリ（テンプレートを読む）
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$REPO_URL" ]; then
  REPO_URL="$(git -C "$HERE" remote get-url origin 2>/dev/null || true)"
  [ -n "$REPO_URL" ] || die "REPO_URL を指定してください（例 REPO_URL=git@github.com:<あなた>/cus-hara.git）"
fi

say "必要なものを入れる（git・curl）"
apt-get update -qq
apt-get install -y -qq git curl ca-certificates >/dev/null

say "Node.js ${NODE_MAJOR}（22.18 以上）"
need_node=1
if command -v node >/dev/null; then
  v="$(node -p 'process.versions.node')"
  IFS=. read -r ma mi _ <<<"$v"
  if [ "$ma" -gt 22 ] || { [ "$ma" -eq 22 ] && [ "$mi" -ge 18 ]; }; then need_node=0; fi
  echo "いまの Node.js: $v"
fi
if [ "$need_node" -eq 1 ]; then
  # NodeSource の公式の手順（https://github.com/nodesource/distributions）
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y -qq nodejs >/dev/null
fi
[ -x /usr/bin/node ] || die "/usr/bin/node がありません（systemd はここを使います）"
echo "Node.js: $(node -v)"

# 本番・テスト（名前 / 置き場所 / ゲームのポート / 管理画面のポート）
ENVS=(
  "cushara /opt/cus-hara 8787 8790 本番"
  "cushara-test /opt/cus-hara-test 8788 8791 テスト"
)

for e in "${ENVS[@]}"; do
  read -r name dir port aport label <<<"$e"
  say "${label}（${name}）"

  # ゲームのサーバーを動かすだけのユーザー（ログインできない）
  if ! id "$name" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$dir" --shell /usr/sbin/nologin "$name"
    echo "ユーザー ${name} を作りました"
  fi

  # プログラム（root の持ち物）
  if [ ! -d "$dir/.git" ]; then
    git clone --quiet --branch "$BRANCH" "$REPO_URL" "$dir" || die "git clone に失敗しました。非公開のリポジトリなら、root の SSH の鍵（デプロイキー）を GitHub に登録してください（docs/HOME_SERVER.md 2節）"
  else
    git -C "$dir" fetch --quiet origin "$BRANCH"
    # サーバーの上では書きかえない前提なので、ブランチの最新にそろえる
    git -C "$dir" checkout --quiet -B "$BRANCH" FETCH_HEAD
  fi
  # var（データ）以外を root の持ち物に
  find "$dir" -path "$dir/server/var" -prune -o -exec chown -h root:root {} +
  echo "版: $(git -C "$dir" log -1 --format='%h %s')"
  (cd "$dir/server" && npm ci --omit=dev --no-audit --no-fund --silent)

  # データ（DB・APIキー・管理画面のパスワード）。このユーザーだけが読み書きできる
  install -d -m 700 -o "$name" -g "$name" "$dir/server/var"

  # systemd のサービス
  unit="/etc/systemd/system/${name}.service"
  sed -e "s#^User=.*#User=${name}#" \
      -e "s#^WorkingDirectory=.*#WorkingDirectory=${dir}/server#" \
      -e "s#^Environment=PORT=.*#Environment=PORT=${port}#" \
      -e "s#^Environment=ADMIN_PORT=.*#Environment=ADMIN_PORT=${aport}#" \
      -e "s#^ReadWritePaths=.*#ReadWritePaths=${dir}/server/var#" \
      -e "s#^Description=.*#Description=Cushara game server (${name})#" \
      "$HERE/deploy/systemd/cushara.service" > "$unit"
  systemctl daemon-reload
  systemctl enable --quiet "$name"
  systemctl restart "$name"

  # 起動を待って確かめる
  ok=0
  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" -eq 1 ] || { journalctl -u "$name" -n 30 --no-pager; die "${label}のサーバーが起動しませんでした（上のログを見てください）"; }
  echo "動いています: http://127.0.0.1:${port}/api/v1/info"
  if [ -f "$dir/server/var/admin_initial_password.txt" ]; then
    echo "管理画面（127.0.0.1:${aport}）の最初のパスワード: sudo cat $dir/server/var/admin_initial_password.txt"
  fi
done

# 更新用のコマンドを置く
install -m 755 "$HERE/deploy/linux/update.sh" /usr/local/sbin/cushara-update

say "できました"
cat <<EOF
本番:   サービス cushara       ゲーム 127.0.0.1:8787  管理画面 127.0.0.1:8790
テスト: サービス cushara-test  ゲーム 127.0.0.1:8788  管理画面 127.0.0.1:8791
更新:   sudo cushara-update test   （本番は sudo cushara-update prod、両方は all）
ログ:   journalctl -u cushara -f   /   journalctl -u cushara-test -f

次にすること（docs/HOME_SERVER.md）:
 1. 管理画面のパスワード（上の表示）でログインして、パスワードを変える。本番とテストで別々です。
    家の Windows から: 本番は deploy/windows/admin_tunnel.bat、テストは admin_tunnel_test.bat
 2. 管理画面の「AIのAPI」でキーを登録する（本番とテストで別々）。
 3. 外に公開する（Cloudflare Tunnel。ドメインが決まってから）:
      cloudflared tunnel login
      cloudflared tunnel create cushara
      cloudflared tunnel route dns cushara game.<ドメイン>
      cloudflared tunnel route dns cushara test.<ドメイン>
    /etc/cloudflared/config.yml は deploy/systemd/cloudflared-config.yml を写して、ID とドメインを書きかえる。
    ★ 向けるのはゲームのポート（8787・8788）だけ。管理画面（8790・8791）は絶対に書かない。
EOF
