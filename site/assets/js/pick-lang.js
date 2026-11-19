/* ルート（/）: 覚えている言語か、ブラウザの言語のページへ移る。
   JavaScript が無いときは、ページの言語の一覧から選んでもらう。 */
(function () {
  "use strict";
  var have = { ja: 1, en: 1, zh: 1, ko: 1 };
  var pick = null;
  try { pick = localStorage.getItem("lang"); } catch (e) { pick = null; }
  if (!have[pick]) {
    pick = "en";
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    for (var i = 0; i < list.length; i++) {
      var l = String(list[i]).toLowerCase().split("-")[0];
      if (have[l]) { pick = l; break; }
    }
  }
  // 検索エンジンのクローラーなどで止まらないよう、置きかえで移る
  location.replace("/" + pick + "/");
})();
