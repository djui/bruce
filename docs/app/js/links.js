// Pure share-link routing (no DOM, runs under Node): https://djui.github.io/bruce/app/#challenge/<id> opens the
// challenge in the Friends tab (a preview with Join for someone who is not in it yet).

export const SHARE_BASE = 'https://djui.github.io/bruce/app/';

/** The challenge id of a "#challenge/<id>" hash, else null. */
export function challengeIdFromHash(hash) {
  const m = /^#?\/?challenge\/([A-Za-z0-9_-]{4,64})\/?$/.exec(String(hash || ''));
  return m ? m[1] : null;
}
export const challengeShareUrl = (id) => SHARE_BASE + '#challenge/' + id;
/** Where the app shows a challenge: the Friends tab, Challenges segment, with the challenge as the detail. */
export const challengeRoute = (id) => '#/friends/challenge/' + id + '?tab=challenges';
