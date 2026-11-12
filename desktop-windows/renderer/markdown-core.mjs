// Markdown for Bot replies (0.9.5): a small, predictable subset parsed into plain data. markdown.js turns it into
// DOM nodes with textContent only, so a reply can never inject HTML or script. No DOM here, so Node can test it.

/** Inline spans: text, code, strong, em, strike, link {href}, image {src, alt}. */
export function parseInline(text) {
  const out = [];
  const value = String(text ?? '');
  const pattern = /(`+)([\s\S]*?)\1|!\[([^\]]*)\]\(([^)\s]+)\)|\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|\*\*([^*]+)\*\*|__([^_]+)__|~~([^~]+)~~|(?<![\w*])\*([^*\n]+)\*(?![\w*])|(?<![\w_])_([^_\n]+)_(?![\w_])|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;
  let last = 0, match;
  while ((match = pattern.exec(value))) {
    if (match.index > last) out.push({ type: 'text', text: value.slice(last, match.index) });
    if (match[1]) out.push({ type: 'code', text: match[2] });
    else if (match[4] !== undefined) out.push({ type: 'image', alt: match[3], src: match[4] });
    else if (match[6]) out.push({ type: 'link', href: match[6], children: parseInline(match[5]) });
    else if (match[7] || match[8]) out.push({ type: 'strong', children: parseInline(match[7] || match[8]) });
    else if (match[9]) out.push({ type: 'strike', children: parseInline(match[9]) });
    else if (match[10] || match[11]) out.push({ type: 'em', children: parseInline(match[10] || match[11]) });
    else if (match[12]) out.push({ type: 'link', href: match[12], children: [{ type: 'text', text: match[12] }] });
    last = pattern.lastIndex;
  }
  if (last < value.length) out.push({ type: 'text', text: value.slice(last) });
  return out;
}

const tableRow = line => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(cell => cell.trim());

/** Blocks: heading {level}, paragraph, code {lang, text}, list {ordered, start, items: [{children, sub}]}, quote, table {head, rows, align}, rule. */
export function parseMarkdown(text) {
  const lines = String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
  const blocks = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const fence = /^\s*(```+|~~~+)\s*([\w+#.-]*)\s*$/.exec(line);
    if (fence) {
      const body = []; i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) body.push(lines[i++]);
      i++; // closing fence (or end while streaming)
      blocks.push({ type: 'code', lang: fence[2].toLowerCase(), text: body.join('\n') });
      continue;
    }
    if (!line.trim()) { i++; continue; }
    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) { blocks.push({ type: 'heading', level: heading[1].length, children: parseInline(heading[2].replace(/\s+#+\s*$/, '')) }); i++; continue; }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { blocks.push({ type: 'rule' }); i++; continue; }
    if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/.test(lines[i + 1])) {
      const head = tableRow(line), align = tableRow(lines[i + 1]).map(cell => cell.startsWith(':') && cell.endsWith(':') ? 'center' : cell.endsWith(':') ? 'right' : 'left');
      const rows = []; i += 2;
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(tableRow(lines[i++]).map(parseInline));
      blocks.push({ type: 'table', head: head.map(parseInline), rows, align });
      continue;
    }
    if (/^\s*>/.test(line)) {
      const body = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ''));
      blocks.push({ type: 'quote', blocks: parseMarkdown(body.join('\n')) });
      continue;
    }
    const item = /^(\s*)([-*+]|(\d{1,3})[.)])\s+(.*)$/.exec(line);
    if (item) {
      const ordered = !!item[3], baseIndent = item[1].length, items = [];
      while (i < lines.length) {
        const next = /^(\s*)([-*+]|(\d{1,3})[.)])\s+(.*)$/.exec(lines[i]);
        if (next && next[1].length <= baseIndent + 1 && !!next[3] === ordered) { items.push({ children: parseInline(next[4]), sub: [] }); i++; continue; }
        if (next && next[1].length > baseIndent + 1 && items.length) { items.at(-1).sub.push(lines[i].slice(baseIndent + 2)); i++; continue; }
        if (lines[i].trim() && /^\s{2,}\S/.test(lines[i]) && items.length) { items.at(-1).children.push({ type: 'text', text: ' ' }, ...parseInline(lines[i].trim())); i++; continue; }
        break;
      }
      for (const entry of items) entry.sub = entry.sub.length ? parseMarkdown(entry.sub.join('\n')) : [];
      blocks.push({ type: 'list', ordered, start: ordered ? Number(item[3]) : 1, items });
      continue;
    }
    const body = [line]; i++;
    while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|\s*```|\s*>|\s*([-*+]|\d{1,3}[.)])\s|\s*\|)/.test(lines[i])) body.push(lines[i++]);
    blocks.push({ type: 'paragraph', children: parseInline(body.join('\n')) });
  }
  return blocks;
}

const KEYWORDS = new Set('abstract and as async await break case catch class const continue def default defer del do elif else enum export extends false final finally fn for from func function go guard if impl import in interface is lambda let match mut new nil none not null or package pass private protected pub public raise return self static struct super switch this throw true try type typeof undefined use var void where while with yield'.split(' '));

/** Code split into tokens for colouring: keyword, string, comment, number, plain. Language-agnostic and safe. */
export function highlight(code) {
  const tokens = [];
  const pattern = /(\/\/[^\n]*|#(?!include)[^\n]*|\/\*[\s\S]*?\*\/|--[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)|\b(\d+(?:\.\d+)?)\b|\b([A-Za-z_][A-Za-z0-9_]*)\b/g;
  let last = 0, match;
  while ((match = pattern.exec(code))) {
    if (match.index > last) tokens.push({ type: 'plain', text: code.slice(last, match.index) });
    if (match[1]) tokens.push({ type: 'comment', text: match[1] });
    else if (match[2]) tokens.push({ type: 'string', text: match[2] });
    else if (match[3]) tokens.push({ type: 'number', text: match[3] });
    else tokens.push({ type: KEYWORDS.has(match[4]) ? 'keyword' : 'plain', text: match[4] });
    last = pattern.lastIndex;
  }
  if (last < code.length) tokens.push({ type: 'plain', text: code.slice(last) });
  return tokens;
}
