// Strike rules for cancelling a booking (Logic.swift `BookingRules.cancelStrikes`, Copy.swift). Bruce's rules since
// June 2026, the same in Sweden, Norway and Denmark: cancelling is free until the class's late-cancel time (12 h
// before), costs 1 strike until 3 h before, 2 until 1 h before, then 3, as much as a no-show. 3 strikes pause class
// booking for 14 days; one strike expires every 30 days. Pure: no DOM, no store (tests in test/logic.test.js).

export const STRIKES_TO_BLOCK = 3;
export const BLOCK_DAYS = 14;
export const STRIKE_EXPIRY_DAYS = 30;
export const NO_SHOW_STRIKES = 3;

/** Strikes a cancellation costs at `now` (ms) for the rule times from store.js `rules(c)`. */
export function cancelStrikes(r, now) {
  if (now < r.lateCancel) return 0;
  if (now < r.shortNotice) return 1;
  if (now < r.lastMinute) return 2;
  return 3;
}

/** When the cost of cancelling next goes up: `{at, strikes}`, or null once it is at its highest. */
export function nextCancelStep(r, now) {
  if (now < r.lateCancel) return { at: r.lateCancel, strikes: 1 };
  if (now < r.shortNotice) return { at: r.shortNotice, strikes: 2 };
  if (now < r.lastMinute) return { at: r.lastMinute, strikes: 3 };
  return null;
}

/** "Cancelling now is free." / "Cancelling now costs 2 strikes." */
export function cancelCost(strikes) {
  return strikes <= 0 ? 'Cancelling now is free.' : 'Cancelling now costs ' + strikes + ' strike' + (strikes === 1 ? '' : 's') + '.';
}

/** The policy list for the account sheet, in our own words. */
export const POLICY = [
  'Late cancellation (3 to 12 hours before) or late check-in: 1 strike',
  'Short-notice cancellation (1 to 3 hours before): 2 strikes',
  'Last-minute cancellation (under 1 hour before) or no-show: 3 strikes',
  'At ' + STRIKES_TO_BLOCK + ' strikes, class booking pauses for ' + BLOCK_DAYS + ' days. One strike expires every ' + STRIKE_EXPIRY_DAYS + ' days.',
];
