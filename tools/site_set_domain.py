#!/usr/bin/env python3
"""紹介サイト（site/）の仮の値を、本番の値に書きかえる。

使い方（リポジトリの一番上で）:
  python3 tools/site_set_domain.py --show
  python3 tools/site_set_domain.py --domain https://kasuhara.example.com
  python3 tools/site_set_domain.py --store-url https://apps.microsoft.com/detail/9XXXXXXXXXXX
  python3 tools/site_set_domain.py --game-server https://game.example.net
  python3 tools/site_set_domain.py --email support@example.net

いま入っている値は site/ の中から読み取るので、何度でも実行できる（前の値 → 新しい値）。
  --domain       サイトのドメイン（canonical・hreflang・OGP・sitemap.xml・robots.txt・JSON-LD）
  --store-url    Microsoft Store のページ（「Microsoft Store で入手」のボタン・JSON-LD）
  --game-server  ゲームサーバーの URL（プライバシーポリシーのページにある、ゲーム内と同じページへのリンク）
  --email        連絡先のメールアドレス（お問い合わせ・規約・プライバシーポリシー・フッター）
"""
import argparse
import html
import pathlib
import re
import sys

SITE = pathlib.Path(__file__).resolve().parent.parent / "site"
TEXT = {".html", ".xml", ".txt", ".js", ".css"}
MAIL_RE = re.compile(r'<(span|a) class="mail[^"]*"[^>]*>.*?</\1>', re.S)


def files():
    for p in sorted(SITE.rglob("*")):
        if p.is_file() and (p.suffix in TEXT or p.name == "_headers"):
            yield p


def current():
    home = (SITE / "ja" / "index.html").read_text(encoding="utf-8")
    priv = (SITE / "ja" / "privacy" / "index.html").read_text(encoding="utf-8")
    dom = re.search(r'<link rel="canonical" href="(https?://[^/"]+)/', home).group(1)
    store = re.search(r'class="btn-primary js-store" href="([^"]+)"', home).group(1)
    game = re.search(r'href="(https?://[^/"]+)/privacy\?lang=', priv).group(1)
    m = re.search(r'href="mailto:([^"]+)"', home)
    return {"domain": dom, "store": html.unescape(store), "game": game, "email": m.group(1) if m else None}


def origin(v, name):
    v = v.rstrip("/")
    if not re.fullmatch(r"https://[A-Za-z0-9.-]+(:\d+)?", v):
        sys.exit("%s は https://ドメイン の形で書いてください（最後の / やパスは不要）: %s" % (name, v))
    return v


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--domain")
    ap.add_argument("--store-url")
    ap.add_argument("--game-server")
    ap.add_argument("--email")
    ap.add_argument("--show", action="store_true", help="いまの値を表示するだけ")
    a = ap.parse_args()
    cur = current()
    if a.show or not any([a.domain, a.store_url, a.game_server, a.email]):
        for k, v in cur.items():
            print("%-7s %s" % (k, v if v else "（未設定: 〔連絡先メールアドレス〕のまま）"))
        return
    reps = []  # (古い文字列, 新しい文字列)
    if a.domain:
        reps.append((cur["domain"] + "/", origin(a.domain, "--domain") + "/"))
    if a.store_url:
        if not a.store_url.startswith("https://"):
            sys.exit("--store-url は https:// で始めてください")
        reps.append((html.escape(cur["store"]), html.escape(a.store_url)))
        reps.append((cur["store"], a.store_url))
    if a.game_server:
        reps.append((cur["game"] + "/privacy?lang=", origin(a.game_server, "--game-server") + "/privacy?lang="))
        # サーバーの状況のページが読む先と、それを許す CSP（_headers の connect-src）
        reps.append((cur["game"] + "/api/v1/status", origin(a.game_server, "--game-server") + "/api/v1/status"))
        reps.append(("connect-src 'self' " + cur["game"], "connect-src 'self' " + origin(a.game_server, "--game-server")))
    if a.email and not re.fullmatch(r"[^@\s<>\"']+@[^@\s<>\"']+\.[A-Za-z]{2,}", a.email):
        sys.exit("--email の形が正しくありません: %s" % a.email)
    changed = 0
    for p in files():
        s = p.read_text(encoding="utf-8")
        t = s
        for old, new in reps:
            t = t.replace(old, new)
        if a.email:
            e = html.escape(a.email)
            t = MAIL_RE.sub('<a class="mail" href="mailto:%s">%s</a>' % (e, e), t)
        if t != s:
            p.write_text(t, encoding="utf-8")
            changed += 1
            print("書きかえ:", p.relative_to(SITE.parent))
    print("%d ファイルを書きかえました。" % changed)


if __name__ == "__main__":
    main()
