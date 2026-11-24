#!/usr/bin/env bash
# カスハラ防衛線: 本番・テストのゲームサーバーをブランチの最新にする（要件#118）。setup.sh が /usr/local/sbin/cushara-update に置く。
#   sudo cushara-update test    テストだけ
#   sudo cushara-update prod    本番だけ
#   sudo cushara-update all     両方
# 管理画面で変えた設定（DB）・APIキー（var/secrets.json）・管理画面のパスワードは、更新しても残る。
# 更新のあと起動しなかったら、前の版に戻して起動し直す。
set -euo pipefail
BRANCH="${BRANCH:-claude/wizardly-keller-c3rj2v}"
[ "$(id -u)" -eq 0 ] || { echo "root で流してください（sudo cushara-update ${1:-test}）" >&2; exit 1; }

update_one() {
  local name="$1" dir="$2" port="$3" label="$4"
  echo "== ${label}（${name}）"
  [ -d "$dir/.git" ] || { echo "${dir} がありません。先に deploy/linux/setup.sh を流してください" >&2; return 1; }
  local before
  before="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" fetch --quiet origin "$BRANCH"
  git -C "$dir" checkout --quiet -B "$BRANCH" FETCH_HEAD
  if [ "$(git -C "$dir" rev-parse HEAD)" = "$before" ]; then
    echo "もう最新です（$(git -C "$dir" log -1 --format='%h %s')）"
    return 0
  fi
  echo "$(git -C "$dir" log -1 --format='%h %s' "$before") → $(git -C "$dir" log -1 --format='%h %s')"
  (cd "$dir/server" && npm ci --omit=dev --no-audit --no-fund --silent)
  systemctl restart "$name"
  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then echo "動いています"; return 0; fi
    sleep 1
  done
  echo "起動しなかったので、前の版（${before:0:7}）に戻します" >&2
  journalctl -u "$name" -n 20 --no-pager >&2 || true
  git -C "$dir" checkout --quiet -B "$BRANCH" "$before"
  (cd "$dir/server" && npm ci --omit=dev --no-audit --no-fund --silent)
  systemctl restart "$name"
  return 1
}

case "${1:-}" in
  test) update_one cushara-test /opt/cus-hara-test 8788 テスト ;;
  prod) update_one cushara /opt/cus-hara 8787 本番 ;;
  all) update_one cushara-test /opt/cus-hara-test 8788 テスト && update_one cushara /opt/cus-hara 8787 本番 ;;
  *) echo "使い方: sudo cushara-update test | prod | all" >&2; exit 2 ;;
esac
