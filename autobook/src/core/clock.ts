// Injectable clock, so the scheduling and retry logic can be tested without real time passing.

export interface Clock {
  now(): number;
  sleep(ms: number): Promise<void>;
}

export const systemClock: Clock = {
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, Math.max(0, ms))),
};

/**
 * Sleeps until `targetMs`. Long waits are split so a late wake-up (timer drift, a paused laptop)
 * does not overshoot by more than one step; the last stretch is a single short timer.
 */
export async function sleepUntil(clock: Clock, targetMs: number): Promise<void> {
  for (;;) {
    const left = targetMs - clock.now();
    if (left <= 0) return;
    await clock.sleep(left > 30_000 ? left - 20_000 : left);
  }
}
