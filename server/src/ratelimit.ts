// 簡単な回数制限（メモリ上）。key ごとに「window ミリ秒の間に limit 回まで」。
const buckets = new Map<string, number[]>();

/** 覚えておく key の数の上限（要件#108: 分散したアクセスでメモリが増え続けないように。古いものから捨てる） */
const MAX_KEYS = 50_000;

export function allow(key: string, limit: number, windowMs: number): boolean {
  const now = Date.now();
  if (!buckets.has(key) && buckets.size >= MAX_KEYS) {
    const oldest = buckets.keys().next().value;
    if (oldest !== undefined) buckets.delete(oldest);
  }
  const list = (buckets.get(key) ?? []).filter((t) => now - t < windowMs);
  if (list.length >= limit) {
    buckets.set(key, list);
    return false;
  }
  list.push(now);
  buckets.delete(key);   // 入れ直して「最近使った」順にする
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
