/* ルート（/）: 毎回、ブラウザの言語のページへ移る（要件#126。前に選んだ言語は使わない）。
   JavaScript が無いときは、ページの言語の一覧から選んでもらう。 */
(function () {
  "use strict";
  var have = { ja: 1, en: 1, zh: 1, ko: 1 };
  var pick = "en";
  var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
  for (var i = 0; i < list.length; i++) {
    var l = String(list[i]).toLowerCase().split("-")[0];
    if (have[l]) { pick = l; break; }
  }
  // ルートから来た人は、言語のページで「初めて」として移し直さない
  try { localStorage.setItem("visited", "1"); } catch (e) { /* 覚えられなくてもよい */ }
  // 検索エンジンのクローラーなどで止まらないよう、置きかえで移る
  location.replace("/" + pick + "/");
})();
