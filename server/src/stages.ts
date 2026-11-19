// 開いている店（要件#102）。コンビニは管理画面の「コンビニを開ける」がオンのときだけ
import { STAGES, type StageId } from "./scenarios.ts";
import { runtime } from "./settings.ts";

export function openStages(): StageId[] {
  return STAGES.filter((s) => s !== "konbini" || runtime.konbiniOpen);
}
