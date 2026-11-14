'use strict';
// Per-message answer modes (Think, Deep Search) and the rule that web answers cite their sources.
// These are prompt notes: they work with every provider because they only add instructions.

const MODES = Object.freeze({
  think: {
    label: 'Think',
    note: '\nTHINK MODE: The human wants you to reason carefully. Work the problem step by step before you answer: check each step and any arithmetic, consider at least one alternative, and say what you are unsure of. Lead with the conclusion, then give the key steps briefly. Do not pad.'
  },
  deep: {
    label: 'Deep Search',
    note: '\nDEEP SEARCH MODE: The human wants thorough, sourced research. Use the web tools: run several search_web queries with different wording (three or more unless the question is simple, and no more than six), open the most relevant pages with browse_web, and cross-check claims between sources. Prefer primary and recent sources and say where they disagree. Finish with a structured answer in which every factual claim carries a [n] citation, followed by a Sources list.'
  }
});

const CITATION_RULE = '\nCitations: when your answer uses web search results, feed items or opened pages, cite them. Numbered results arrive as "1. Title — link"; put the number in square brackets right after the claim it supports, like [1] or [2][3]. End with a short "Sources" list of "[n] Title — link" for the numbers you used. Cite only sources you actually received, never invent links, and do not cite for things you know without a lookup.';

/** The known mode name, or null. */
const normalize = mode => (typeof mode === 'string' && Object.hasOwn(MODES, mode) ? mode : null);
const noteFor = mode => { const name = normalize(mode); return name ? MODES[name].note : ''; };

/** Numbered lines the Bot can cite, shared by web search and feeds so the numbers always mean the same thing. */
function numbered(items) {
  return items.map((item, index) => `${index + 1}. ${item.title} — ${item.url}${item.snippet ? ` — ${item.snippet}` : ''}`).join('\n');
}

module.exports = { MODES, CITATION_RULE, normalize, noteFor, numbered };
