#!/usr/bin/env python3
"""画面の文言の翻訳キーを集め、訳漏れを調べる。

使い方:
  python3 tools/i18n.py list           翻訳が必要な日本語の文を一覧する
  python3 tools/i18n.py check          data/i18n/<言語>.json に訳が無い文があれば一覧して終了コード1（CI用）
  python3 tools/i18n.py missing en     訳が無い文だけを JSON で出す（翻訳作業用）

集める文:
  1. tr("…") の中の文字列
  2. 画面に出す定数（STAGES など）と、画面のスクリプトにある日本語の文字列
     （ただし自動テスト用の関数の中と、print の行と、コメントは除く）
  3. サーバーが返すランク名（server/src/rating.ts）
"""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = ["en"]
UI_FILES = ["main.gd", "hud.gd", "solo_game.gd", "versus_game.gd", "game_settings.gd", "ui_paper.gd", "server_api.gd", "shop_actions.gd", "crane_minigame.gd", "eos_matchmaker.gd"]
SKIP_FUNCS = ("_smoke_autoplay", "_run_shots", "_run_smoke", "_run_versus_smoke")
JA = re.compile(r"[぀-ヿ㐀-鿿！-｠]")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
TR = re.compile(r'tr\("((?:[^"\\]|\\.)*)"\)')


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def keys():
    found = {}
    for path in sorted((ROOT / "scripts").glob("*.gd")):
        in_skip = False
        for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.split("#")[0] if not raw.strip().startswith("#") else ""
            if raw.startswith("func "):
                in_skip = raw[5:].startswith(SKIP_FUNCS)
            for m in TR.finditer(raw):
                found.setdefault(unescape(m.group(1)), f"{path.name}:{n}")
            if path.name not in UI_FILES or in_skip or "print(" in line:
                continue
            for m in STR.finditer(line):
                s = unescape(m.group(1))
                if JA.search(s):
                    found.setdefault(s, f"{path.name}:{n}")
    rating = (ROOT / "server" / "src" / "rating.ts").read_text(encoding="utf-8")
    for m in re.finditer(r'"([^"]*)"\]', rating):
        if JA.search(m.group(1)):
            found.setdefault(m.group(1), "server/src/rating.ts")
    return found


def load(lang):
    p = ROOT / "data" / "i18n" / f"{lang}.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    k = keys()
    if cmd == "list":
        for s, where in k.items():
            print(f"{where}\t{s}")
    elif cmd == "missing":
        lang = sys.argv[2]
        tr = load(lang)
        print(json.dumps({s: "" for s in k if s not in tr}, ensure_ascii=False, indent="\t"))
    else:
        bad = 0
        for lang in LANGS:
            tr = load(lang)
            for s, where in k.items():
                if not tr.get(s):
                    print(f"[{lang}] 訳がありません: {where}  {s!r}")
                    bad += 1
        print(f"{len(k)} 件の文を確認、訳漏れ {bad} 件")
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
