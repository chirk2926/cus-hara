/* 言語のページ（/ja/ など）: そのブラウザで初めてサイトに来たときだけ、ブラウザの言語の同じページへ移る（要件#126）。
   2回目からは URL のとおりに出す。移る先は、ページの hreflang の別ページ（その言語の記事が無ければ移らない）。
   検索エンジンのクローラーは移さない（どの言語のページも読めるように）。<head> の中で、hreflang の後・CSS の前に読む */
(function () {
  "use strict";
  try {
    if (/bot|crawl|spider|slurp|google|bing|yandex|baidu|duckduck|facebookexternalhit|twitterbot|lighthouse/i.test(navigator.userAgent || "")) return;
    if (localStorage.getItem("visited")) return;
    localStorage.setItem("visited", "1");
  } catch (e) {
    return; // 覚えられないブラウザでは、毎回移らないように何もしない
  }
  var have = { ja: "ja", en: "en", zh: "zh-Hans", ko: "ko" };
  var want = "en";
  var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
  for (var i = 0; i < list.length; i++) {
    var l = String(list[i]).toLowerCase().split("-")[0];
    if (have[l]) { want = l; break; }
  }
  var now = (location.pathname.match(/^\/(ja|en|zh|ko)\//) || [])[1];
  if (!now || now === want) return;
  var alt = document.querySelector('link[rel="alternate"][hreflang="' + have[want] + '"]');
  if (!alt) return;
  var to = new URL(alt.getAttribute("href"), location.href);
  location.replace(to.pathname + location.search + location.hash);
})();
