#!/usr/bin/env node
// Link check for the race catalog (docs/app/races.json). The maintainer runs it by hand before updating the catalog;
// nothing runs it automatically (not CI, not the tests, not the apps or the server):
//
//   node scripts/check-races.mjs                 check every race's signupUrl
//   node scripts/check-races.mjs --only <id>     one race
//   node scripts/check-races.mjs --dry-run       list what would be fetched, fetch only robots.txt
//
// For every distinct link it reads that host's robots.txt once and honours it for our user agent (Disallow, Allow
// and Crawl-delay; a delay over a minute means "check by hand"), never contacts registration or results platforms,
// sends one GET with a named User-Agent and reports the HTTP status and whether the race date appears in the page.
// It never edits the catalog: a changed date or price is for the maintainer to read on the page and fix by hand.

import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

export const USER_AGENT = 'BruceRaceCheck/1.0 (+https://github.com/djui/bruce; hand-run catalog link check)';
/** The product token robots.txt groups are matched against. */
export const AGENT = 'BruceRaceCheck';
/** Registration, ticketing and results platforms: never fetched (the race's own page is the source). */
export const PLATFORM_HOSTS = ['vivenu.com', 'raceid.com', 'njuko.com', 'njuko.net', 'onreg.com', 'sportstiming.dk', 'sportstiming.se',
  'sportstiming.no', 'eqtiming.com', 'eqtiming.no', 'raceresult.com', 'letsdothis.com', 'ahotu.com', 'haku.se', 'hakuapp.com', 'queue-it.net'];
const MAX_DELAY_S = 60;
const PAUSE_MS = 1500;

export const isPlatformHost = (host) => PLATFORM_HOSTS.some((h) => host === h || host.endsWith('.' + h));

// ---------------------------------------------------------------- robots.txt (RFC 9309)

/** Groups of a robots.txt: [{agents: ["*"], rules: [{allow, path}], delay}]. */
export function parseRobots(text) {
  const groups = [];
  let g = null, lastWasAgent = false;
  for (const raw of String(text || '').split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, '').trim();
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.*)$/);
    if (!m) continue;
    const key = m[1].toLowerCase(), value = m[2].trim();
    if (key === 'user-agent') {
      if (!g || !lastWasAgent) { g = { agents: [], rules: [], delay: null }; groups.push(g); }
      g.agents.push(value.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (!g) continue;
    if (key === 'allow' || key === 'disallow') { if (value || key === 'allow') g.rules.push({ allow: key === 'allow', path: value }); }
    else if (key === 'crawl-delay') { const d = parseFloat(value); if (!isNaN(d)) g.delay = d; }
  }
  return groups;
}

/** Robots path pattern ("*" wildcard, "$" end) against a path with its query. */
function patternMatches(pattern, p) {
  if (!pattern) return false;
  const anchored = pattern.endsWith('$');
  const body = (anchored ? pattern.slice(0, -1) : pattern).split('*').map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*');
  return new RegExp('^' + body + (anchored ? '$' : '')).test(p);
}

/** {allowed, delay} for our agent and a path: the most specific rule wins, Allow wins a tie, nothing listed is allowed. */
export function robotsVerdict(text, agent, pathAndQuery) {
  const groups = parseRobots(text);
  const token = agent.toLowerCase();
  let mine = groups.filter((g) => g.agents.includes(token));
  if (!mine.length) mine = groups.filter((g) => g.agents.includes('*'));
  const rules = mine.flatMap((g) => g.rules);
  const delays = mine.map((g) => g.delay).filter((d) => d != null);
  let best = null;
  for (const r of rules) {
    if (!r.path) continue;
    if (!patternMatches(r.path, pathAndQuery)) continue;
    if (!best || r.path.length > best.path.length || (r.path.length === best.path.length && r.allow)) best = r;
  }
  return { allowed: !best || best.allow, delay: delays.length ? Math.max(...delays) : null };
}

// ---------------------------------------------------------------- date in the page

const MONTHS = {
  en: ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'],
  sv: ['januari', 'februari', 'mars', 'april', 'maj', 'juni', 'juli', 'augusti', 'september', 'oktober', 'november', 'december'],
  no: ['januar', 'februar', 'mars', 'april', 'mai', 'juni', 'juli', 'august', 'september', 'oktober', 'november', 'desember'],
  da: ['januar', 'februar', 'marts', 'april', 'maj', 'juni', 'juli', 'august', 'september', 'oktober', 'november', 'december'],
};

/** Ways a page may write a day (lower case): "2027-05-15", "15.05.2027", "15 may 2027", "may 15", "15 maj", "15. mai". */
export function datePatterns(day) {
  const [y, mo, d] = day.split('-').map(Number);
  const dd = String(d).padStart(2, '0'), mm = String(mo).padStart(2, '0');
  const out = new Set([day, dd + '.' + mm + '.' + y, d + '.' + mo + '.' + y, dd + '/' + mm + '/' + y, d + '/' + mo + '/' + y]);
  for (const names of Object.values(MONTHS)) {
    const full = names[mo - 1], short = full.slice(0, 3);
    for (const mon of new Set([full, short])) {
      out.add(d + ' ' + mon + ' ' + y); out.add(d + '. ' + mon + ' ' + y); out.add(d + ' ' + mon); out.add(d + '. ' + mon);
      out.add(mon + ' ' + d + ', ' + y); out.add(mon + ' ' + d);
    }
  }
  return [...out];
}

/** The page's visible text in lower case, one space between words. */
export function pageText(html) {
  return String(html || '').replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ').replace(/&amp;/gi, '&').replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n))
    .replace(/\s+/g, ' ').toLowerCase();
}

/** Whether the race's (first or last) day appears in the page: as text, or as an ISO date anywhere (JSON-LD). */
export function dateSeen(html, race) {
  const text = pageText(html);
  const days = [race.date].concat(race.endDate && race.endDate !== race.date ? [race.endDate] : []);
  return days.some((day) => String(html || '').includes(day) ||
    datePatterns(day).some((p) => new RegExp('(^|[^0-9a-zåäöæø])' + p.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '($|[^0-9a-zåäöæø])').test(text)));
}

// ---------------------------------------------------------------- the run

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(url, accept) {
  return fetch(url, { redirect: 'manual', headers: { 'User-Agent': USER_AGENT, Accept: accept }, signal: AbortSignal.timeout(15000) });
}

async function main(argv) {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const fileArg = argv.indexOf('--file');
  const file = fileArg >= 0 ? argv[fileArg + 1] : path.join(here, '..', 'docs', 'app', 'races.json');
  const onlyArg = argv.indexOf('--only');
  const only = onlyArg >= 0 ? argv[onlyArg + 1] : null;
  const dry = argv.includes('--dry-run');
  const catalog = JSON.parse(await readFile(file, 'utf8'));
  const races = catalog.races.filter((r) => !only || r.id === only);
  if (!races.length) { console.error('No race ' + only); process.exit(2); }

  const byUrl = new Map();
  for (const r of races) { if (!byUrl.has(r.signupUrl)) byUrl.set(r.signupUrl, []); byUrl.get(r.signupUrl).push(r); }
  const robots = new Map();   // host -> text ('' when there is none)
  const lastHit = new Map();  // host -> time of the last request
  const results = [];

  /** The host's robots.txt, following up to five redirects (RFC 9309 2.3.1.2). Missing (4xx) means no rules; server
   *  trouble, a network error or more redirects means "keep out" (2.3.1.4). */
  async function robotsFor(u) {
    if (robots.has(u.host)) return robots.get(u.host);
    const keepOut = 'User-agent: *\nDisallow: /';
    let text = keepOut;
    try {
      let at = new URL('/robots.txt', u.origin);
      for (let hop = 0; hop <= 5; hop++) {
        const res = await get(at.href, 'text/plain');
        lastHit.set(at.host, Date.now());
        if (res.status >= 300 && res.status < 400 && res.headers.get('location')) { at = new URL(res.headers.get('location'), at); continue; }
        if (res.status >= 200 && res.status < 300) text = await res.text();
        else if (res.status >= 400 && res.status < 500) text = '';
        break;
      }
    } catch (e) { text = keepOut; }
    robots.set(u.host, text);
    return text;
  }

  for (const [link, list] of byUrl) {
    let url = new URL(link);
    let outcome = null;
    for (let hop = 0; hop < 4 && !outcome; hop++) {
      if (url.protocol !== 'https:') { outcome = { kind: 'problem', note: 'not https: ' + url.href }; break; }
      if (isPlatformHost(url.hostname)) { outcome = { kind: 'skipped', note: 'registration platform ' + url.hostname + ', not fetched' }; break; }
      const v = robotsVerdict(await robotsFor(url), AGENT, url.pathname + url.search);
      if (!v.allowed) { outcome = { kind: 'skipped', note: 'robots.txt disallows ' + url.pathname }; break; }
      if (v.delay != null && v.delay > MAX_DELAY_S) { outcome = { kind: 'skipped', note: 'robots.txt asks a ' + v.delay + ' s crawl delay; check by hand' }; break; }
      if (dry) { outcome = { kind: 'dry', note: 'would GET ' + url.href }; break; }
      const wait = Math.max((v.delay || 0) * 1000, PAUSE_MS) - (Date.now() - (lastHit.get(url.host) || 0));
      if (wait > 0) await sleep(wait);
      let res, html = '';
      try {
        res = await get(url.href, 'text/html,application/xhtml+xml');
        lastHit.set(url.host, Date.now());
        if (res.status >= 300 && res.status < 400 && res.headers.get('location')) { url = new URL(res.headers.get('location'), url); continue; }
        if (res.status < 400) html = await res.text();
      } catch (e) { outcome = { kind: 'problem', note: 'network: ' + (e.cause && e.cause.code || e.name || e.message) }; break; }
      outcome = { kind: res.status < 400 ? 'ok' : 'problem', status: res.status, html, final: url.href };
    }
    if (!outcome) outcome = { kind: 'problem', note: 'too many redirects' };
    for (const r of list) {
      const line = { id: r.id, date: r.date, kind: outcome.kind, status: outcome.status || '', note: outcome.note || '' };
      if (outcome.kind === 'ok') {
        line.note = (dateSeen(outcome.html, r) ? 'date seen' : 'date NOT seen, check the page') + (outcome.final !== link ? ' · moved to ' + outcome.final : '');
        if (!dateSeen(outcome.html, r)) line.kind = 'check';
      }
      results.push(line);
      console.log([line.kind.padEnd(7), String(line.status).padEnd(4), r.id.padEnd(32), r.date, line.note].join('  '));
    }
  }
  const problems = results.filter((r) => r.kind === 'problem').length;
  const checks = results.filter((r) => r.kind === 'check').length;
  const skipped = results.filter((r) => r.kind === 'skipped').length;
  console.log('\n' + results.length + ' races, ' + byUrl.size + ' links: ' + problems + ' broken, ' + checks + ' without the date in the page, ' + skipped + ' skipped.');
  process.exitCode = problems ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch((e) => { console.error(e); process.exit(2); });
}
