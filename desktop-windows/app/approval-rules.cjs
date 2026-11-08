'use strict';
const { randomUUID } = require('node:crypto');

/** Things a rule can name on Windows. Clicks that send or buy, typing-and-submitting and saved logins always ask regardless of rules. */
const TOOLS = [['browser_click', 'Click on a web page']];
const MAX_RULES = 60;

/** Only "Always ask" rules exist on Windows: nothing a Bot does here is safe enough to allow without asking. */
function sanitize(value) {
  const rules = [];
  const seen = new Set();
  for (const rule of Array.isArray(value?.rules) ? value.rules : []) {
    if (!rule || rule.kind !== 'ask' || !TOOLS.some(([id]) => id === rule.tool)) continue;
    const pattern = typeof rule.pattern === 'string' ? rule.pattern.trim().slice(0, 120) : '';
    const key = `${rule.tool}|${pattern.toLowerCase()}`;
    if (seen.has(key) || rules.length >= MAX_RULES) continue;
    seen.add(key);
    rules.push({ id: typeof rule.id === 'string' && /^[-\w]{8,64}$/.test(rule.id) ? rule.id : randomUUID(), kind: 'ask', tool: rule.tool, pattern });
  }
  return { enabled: value?.enabled !== false, rules };
}

/** 'ask' when a written rule says to always ask for this tool and target, otherwise 'noRule'. */
function decide(config, tool, target = '') {
  const clean = sanitize(config);
  if (!clean.enabled) return 'noRule';
  const text = String(target).toLowerCase();
  return clean.rules.some(rule => rule.tool === tool && (!rule.pattern || text.includes(rule.pattern.toLowerCase()))) ? 'ask' : 'noRule';
}

module.exports = { TOOLS, MAX_RULES, sanitize, decide };
