export function log(...args: unknown[]): void {
  if (process.env.QUIET === "1") return;
  console.log(new Date().toISOString(), ...args);
}
