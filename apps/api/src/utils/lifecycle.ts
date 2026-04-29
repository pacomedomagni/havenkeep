/// 2.7: shared lifecycle flag so /ready can flip to 503 the moment we
/// start a graceful shutdown — not after the socket close. Exposed as a
/// pair of functions so health.ts doesn't need to import index.ts (and
/// pull the whole bootstrap into the process for a unit test).

let _isShuttingDown = false;

export function markShuttingDown(): void {
  _isShuttingDown = true;
}

export function isShuttingDown(): boolean {
  return _isShuttingDown;
}
