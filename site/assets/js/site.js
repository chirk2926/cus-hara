/* カスハラ防衛線 紹介サイトの仕掛け（ライブラリなし）
   1. 従業員証がゆれる      2. クレーンゲームのフロア案内
   3. スクロールで印字されるレシート  4. お客様表示（怒りメーター）
   5. コルクボードの写真を大きく見る  6. シャッター（コンビニ）  7. 言語の記憶 */
(function () {
  "use strict";
  var doc = document.documentElement;
  doc.classList.remove("no-js");
  var mq = window.matchMedia ? window.matchMedia("(prefers-reduced-motion: reduce)") : null;
  function still() { return !!(mq && mq.matches); }
  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }
  function wait(ms) { return new Promise(function (ok) { setTimeout(ok, ms); }); }

  /* 1. 従業員証 */
  var card = $(".idcard");
  if (card) {
    var swing = function () {
      if (still()) return;
      card.classList.remove("swing");
      void card.offsetWidth; // アニメーションをやり直す
      card.classList.add("swing");
    };
    card.addEventListener("click", swing);
    card.addEventListener("animationend", function () { card.classList.remove("swing"); });
    var hovered = 0;
    card.addEventListener("pointerenter", function (e) {
      if (e.pointerType === "mouse" && Date.now() - hovered > 2500) { hovered = Date.now(); swing(); }
    });
    setTimeout(swing, 400);
  }

  /* 2. クレーンゲームのフロア案内 */
  var crane = $(".crane");
  if (crane) {
    var claw = $(".claw", crane), glass = $(".crane-glass", crane), chute = $(".chute", crane);
    var busy = false;
    var go = function (href) {
      var target = document.getElementById(href.slice(1));
      if (!target) return;
      if (history.pushState) history.pushState(null, "", href); else location.hash = href;
      target.scrollIntoView({ behavior: still() ? "auto" : "smooth", block: "start" });
      if (!target.hasAttribute("tabindex")) target.setAttribute("tabindex", "-1");
      target.focus({ preventScroll: true });
    };
    var xOf = function (el) {
      var g = glass.getBoundingClientRect(), r = el.getBoundingClientRect();
      return r.left - g.left + r.width / 2;
    };
    var reset = function () {
      claw.classList.remove("closed");
      claw.style.setProperty("--drop", "24px");
      claw.style.setProperty("--cx", xOf(chute) + "px");
    };
    claw.style.setProperty("--cx", "40px");
    $$(".prize", crane).forEach(function (p) {
      p.addEventListener("click", function (e) {
        var href = p.getAttribute("href");
        if (still() || busy) { if (busy) e.preventDefault(); if (busy) go(href); return; }
        e.preventDefault();
        busy = true;
        var g = glass.getBoundingClientRect(), r = p.getBoundingClientRect();
        var depth = Math.max(24, r.top - g.top - 34);
        claw.style.setProperty("--cx", xOf(p) + "px");
        wait(620).then(function () {
          claw.style.setProperty("--drop", depth + "px");
          return wait(480);
        }).then(function () {
          claw.classList.add("closed");
          return wait(220);
        }).then(function () {
          claw.style.setProperty("--drop", "24px");
          p.classList.add("held");
          p.style.transform = "translateY(" + (-(depth - 24)) + "px)";
          return wait(480);
        }).then(function () {
          var dx = xOf(chute) - xOf(p);
          claw.style.setProperty("--cx", xOf(chute) + "px");
          p.style.transform = "translate(" + dx + "px," + (-(depth - 24)) + "px)";
          return wait(620);
        }).then(function () {
          claw.classList.remove("closed");
          p.classList.add("gone");
          return wait(260);
        }).then(function () {
          go(href);
          return wait(400);
        }).then(function () {
          p.classList.remove("held", "gone");
          p.style.transform = "";
          reset();
          busy = false;
        });
      });
    });
  }

  /* 3. レシート */
  var receipt = $(".receipt");
  if (receipt && !still()) {
    var clip = receipt.parentNode, ticking = false;
    var print = function () {
      ticking = false;
      var r = clip.getBoundingClientRect(), vh = window.innerHeight;
      var p = (vh * 0.92 - r.top) / (r.height * 0.75 + 1);
      p = Math.max(0.06, Math.min(1, p));
      receipt.style.setProperty("--p", p.toFixed(3));
    };
    var onScroll = function () { if (!ticking) { ticking = true; requestAnimationFrame(print); } };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    print();
  }

  /* 4. お客様表示 */
  var demo = $(".demo");
  if (demo) {
    var st, timer = null, visible = false;
    var bars = { anger: $(".meter.anger", demo), calm: $(".meter.calm", demo) };
    var bubble = $(".bubble q", demo), stamp = $(".stamp", demo), live = $(".demo-live", demo);
    var tags = $$(".tag", demo);
    var lineAngry = bubble ? bubble.textContent : "";
    var segs = function (m) {
      var box = $(".segs", m);
      if (box.children.length === 0) for (var i = 0; i < 20; i++) box.appendChild(document.createElement("i"));
      return box.children;
    };
    var paint = function () {
      [["anger", st.anger], ["calm", st.calm]].forEach(function (a) {
        var m = bars[a[0]], s = segs(m), n = Math.round(a[1] / 5);
        for (var i = 0; i < s.length; i++) s[i].className = i < n ? "on" : "";
        $(".val", m).textContent = Math.round(a[1]);
        m.setAttribute("aria-valuenow", Math.round(a[1]));
      });
    };
    var end = function (kind) {
      st.over = true;
      clearInterval(timer); timer = null;
      tags.forEach(function (t) { t.disabled = true; });
      stamp.textContent = demo.getAttribute("data-" + kind);
      stamp.className = "stamp show" + (kind === "win" ? " ok" : "");
      if (kind === "win" && bubble) bubble.textContent = demo.getAttribute("data-calm-line");
      if (live) live.textContent = stamp.textContent;
    };
    var check = function () {
      st.anger = Math.max(0, Math.min(100, st.anger));
      st.calm = Math.max(0, Math.min(100, st.calm));
      paint();
      if (st.anger >= 100) end("lose");
      else if (st.calm >= 100) end("win");
    };
    var start = function () {
      st = { anger: 42, calm: 0, used: {}, over: false };
      tags.forEach(function (t) { t.disabled = false; });
      stamp.className = "stamp";
      if (bubble) bubble.textContent = lineAngry;
      if (live) live.textContent = "";
      paint();
      tick();
    };
    var tick = function () {
      if (timer || !visible || st.over) return;
      timer = setInterval(function () {
        if (document.hidden) return;
        st.anger += 1; check();
      }, 900);
    };
    var halt = function () { clearInterval(timer); timer = null; };
    tags.forEach(function (t) {
      t.addEventListener("click", function () {
        if (st.over) return;
        var k = t.getAttribute("data-k"), n = st.used[k] = (st.used[k] || 0) + 1;
        var fx = {
          // [イカリ, ナットク]。2回目からは効きが落ちる。謝ってばかりではダメ
          sorry: n === 1 ? [-4, 4] : [7, 0],
          feel: n === 1 ? [-9, 14] : [3, 1],
          ask: n === 1 ? [-4, 10] : [4, 0],
          data: n === 1 ? [-6, 22] : [2, 0],
          move: n === 1 ? [-12, 54] : [0, 4]
        }[k];
        if (k === "refund") { end("cave"); return; }
        if (!fx) return;
        st.anger += fx[0]; st.calm += fx[1];
        check();
      });
    });
    var again = $(".demo-again", demo);
    if (again) again.addEventListener("click", function () { halt(); start(); });
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        visible = es[0].isIntersecting;
        if (visible) tick(); else halt();
      }, { threshold: 0.35 }).observe(demo);
    } else { visible = true; }
    start();
  }

  /* 5. 写真を大きく見る */
  var box = $("dialog.lightbox");
  if (box && typeof box.showModal === "function") {
    var big = $("img", box), cap = $("figcaption", box);
    $$(".pin").forEach(function (a) {
      a.addEventListener("click", function (e) {
        e.preventDefault();
        var img = $("img", a);
        big.src = a.getAttribute("href");
        big.alt = img ? img.alt : "";
        cap.textContent = ($("span", a) || {}).textContent || "";
        box.showModal();
      });
    });
    $("button", box).addEventListener("click", function () { box.close(); });
    box.addEventListener("click", function (e) { if (e.target === box) box.close(); });
  }

  /* 6. シャッター（タップで少し上げる） */
  $$(".shutter-box button").forEach(function (b) {
    b.addEventListener("click", function () {
      var on = b.parentNode.classList.toggle("peek");
      b.setAttribute("aria-pressed", on ? "true" : "false");
    });
  });

  /* 7. 言語を選んだら覚えておく（ルートのページが使う） */
  $$("[data-setlang]").forEach(function (a) {
    a.addEventListener("click", function () {
      try { localStorage.setItem("lang", a.getAttribute("data-setlang")); } catch (e) { /* 使えないときは覚えない */ }
    });
  });
})();
