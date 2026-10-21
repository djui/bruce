// Add to Calendar (Shared/BruceCore/CalendarExport.swift): one booked class as an .ics file the browser downloads,
// and the subscription to Bruce's own feed of all bookings. The feed URL holds the user's secret (API.md: a
// credential): it is only handed to the calendar app or the clipboard, never shown or logged.
// `icsFor` and `feedUrl` are pure (tests in test/logic.test.js); `addToCalendar` touches the DOM.

export const ALERT_MINUTES = 60;
export const ONE_OFF_NOTE = "A single event won't follow changes to the class. Subscribe keeps every booking in sync.";
const FOOTER = "Added with Brüce, an unofficial Bruce Studios client. This event is a copy and doesn't follow changes to the class; the calendar subscription in Settings stays in sync.";

const pad = (n) => String(n).padStart(2, '0');
/** 2026-10-27T17:00:00Z -> 20261027T170000Z */
export function icsTime(ms) {
  const d = new Date(ms);
  return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + 'T' + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + 'Z';
}
const escText = (s) => String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');

/**
 * The event text (RFC 5545) for a class. `o`: {studio (name, address, zip, city), rules (store.js rules(c)),
 * instructor, timeText(ms) -> "17:00", longText(ms) -> "17:00, Tuesday, 27 October", url, now}.
 */
export function icsFor(c, o) {
  const r = o.rules;
  const st = o.studio || {};
  const where = [st.name, st.address, [st.zip, st.city].filter(Boolean).join(' ')].filter(Boolean).join(', ');
  const notes = [];
  if (o.instructor) notes.push('Instructor: ' + o.instructor);
  notes.push('Check-in ' + o.timeText(r.checkInFrom) + '–' + o.timeText(r.lateCheckIn) + ' in the Bruce app at the studio.');
  notes.push('Free cancel until ' + o.longText(r.lateCancel) + '; after that a cancellation costs strikes, a no-show 3.');
  notes.push('', FOOTER);
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Brüce (unofficial)//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT', 'UID:class-' + c.id + '@bruce.unofficial', 'DTSTAMP:' + icsTime(o.now || Date.now()),
    'DTSTART:' + icsTime(r.start), 'DTEND:' + icsTime(r.end || r.start + 3600000), 'SUMMARY:' + escText(c.title)];
  if (where) lines.push('LOCATION:' + escText(where));
  lines.push('DESCRIPTION:' + escText(notes.join('\n')));
  if (o.url) lines.push('URL:' + o.url);
  lines.push('BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:' + escText(c.title), 'TRIGGER:-PT' + ALERT_MINUTES + 'M', 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}

export const RACE_ALERT_MINUTES = 6 * 60;
const RACE_FOOTER = "Added with Brüce, an unofficial Bruce Studios client. Not affiliated with the race or its organiser; check the official page for changes.";

/**
 * A race as an all-day event (races.js): the member's `day` of the event if they picked one, else every day of it,
 * with an alert at 18:00 the evening before. `o`: {day, facts ("8 km · solo, duo, trio or team"), url, now}.
 */
export function icsForRace(r, o) {
  const p = o || {};
  const first = p.day || r.date, last = p.day || r.endDate || r.date;
  const next = new Date(last + 'T12:00:00Z'); next.setUTCDate(next.getUTCDate() + 1);
  const ymd = (d) => d.replace(/-/g, '');
  const notes = [p.facts, p.url ? 'Race page: ' + p.url : null].filter(Boolean).concat(['', RACE_FOOTER]);
  const where = [r.venue, r.city].filter(Boolean).join(', ');
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Brüce (unofficial)//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT', 'UID:race-' + r.id + '@bruce.unofficial', 'DTSTAMP:' + icsTime(p.now || Date.now()),
    'DTSTART;VALUE=DATE:' + ymd(first), 'DTEND;VALUE=DATE:' + ymd(next.toISOString().slice(0, 10)), 'SUMMARY:' + escText(r.name), 'TRANSP:TRANSPARENT'];
  if (where) lines.push('LOCATION:' + escText(where));
  lines.push('DESCRIPTION:' + escText(notes.join('\n')));
  if (p.url) lines.push('URL:' + p.url);
  lines.push('BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:' + escText(r.name), 'TRIGGER:-PT' + RACE_ALERT_MINUTES + 'M', 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}

/** "hot-yoga-2026-10-27.ics" (`dayKey` is the class day as YYYY-MM-DD). */
export function icsFileName(title, dayKey) {
  const slug = String(title).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return (slug || 'class') + '-' + dayKey + '.ics';
}

/** Bruce's feed of all bookings as a webcal:// link, or null before the user record (with its secret) is loaded. */
export function feedUrl(userId, user) {
  if (!userId || !user || !user.secret) return null;
  return 'webcal://api.bruce.app/v52/user/' + userId + '/calendar/' + user.secret + '.ics';
}

/** Lets the browser download (or, on iPhone, open) the event file. */
export function addToCalendar(text, fileName) {
  const blob = new Blob([text], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = fileName; a.rel = 'noopener';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}
