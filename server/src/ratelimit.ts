// 簡単な回数制限（メモリ上）。key ごとに「window ミリ秒の間に limit 回まで」。
const buckets = new Map<string, number[]>();

export function allow(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  const list = (buckets.get(key) ?? []).filter((t) => now - t < windowMs);
  if (list.length >= limit) {
    buckets.set(key, list);
    return false;
  }
  list.push(now);
  buckets.set(key, list);
  return true;
}

// 古い記録を定期的に捨てる
setInterval(() => {
  const now = Date.now();
  for (const [k, list] of buckets) {
    const kept = list.filter((t) => now - t < 3_600_000);
    if (kept.length === 0) buckets.delete(k);
    else buckets.set(k, kept);
  }
}, 600_000).unref();
