// Builds DOM nodes for Bot replies from markdown-core.mjs. Only textContent and safe attributes are used, so a reply
// cannot add HTML, styles or script. Links open in the default browser after a check in the main process; images
// show only files inside the Bot's own folder (read by the main process) or https addresses (shown as links).
import { parseMarkdown, highlight } from './markdown-core.mjs';

const el = (tag, className, text) => { const node = document.createElement(tag); if (className) node.className = className; if (text != null) node.textContent = text; return node; };

function inline(spans, context) {
  const fragment = document.createDocumentFragment();
  for (const span of spans) {
    if (span.type === 'text') fragment.append(document.createTextNode(span.text));
    else if (span.type === 'code') fragment.append(el('code', 'md-code', span.text));
    else if (span.type === 'strong') { const node = el('strong'); node.append(inline(span.children, context)); fragment.append(node); }
    else if (span.type === 'em') { const node = el('em'); node.append(inline(span.children, context)); fragment.append(node); }
    else if (span.type === 'strike') { const node = el('s'); node.append(inline(span.children, context)); fragment.append(node); }
    else if (span.type === 'link') {
      const node = el('a', 'md-link'); node.href = '#'; node.title = span.href; node.append(inline(span.children, context));
      node.addEventListener('click', event => { event.preventDefault(); context.openLink?.(span.href); });
      fragment.append(node);
    } else if (span.type === 'image') {
      const holder = el('span', 'md-image');
      if (/^https?:\/\//.test(span.src)) {
        const link = el('a', 'md-link', span.alt || span.src); link.href = '#'; link.title = span.src;
        link.addEventListener('click', event => { event.preventDefault(); context.openLink?.(span.src); });
        holder.append(link);
      } else if (context.loadImage) {
        holder.append(el('span', 'md-image-alt', span.alt || 'Image'));
        context.loadImage(span.src).then(dataURL => { if (!dataURL) return; const img = el('img'); img.alt = span.alt || ''; img.src = dataURL; holder.replaceChildren(img); }).catch(() => {});
      } else holder.append(el('span', 'md-image-alt', span.alt || 'Image'));
      fragment.append(holder);
    }
  }
  return fragment;
}

function blocks(list, context) {
  const fragment = document.createDocumentFragment();
  for (const block of list) {
    if (block.type === 'paragraph') { const p = el('p', 'md-p'); p.append(inline(block.children, context)); fragment.append(p); }
    else if (block.type === 'heading') { const h = el('h' + Math.min(block.level + 2, 6), 'md-h md-h' + block.level); h.append(inline(block.children, context)); fragment.append(h); }
    else if (block.type === 'rule') fragment.append(el('hr', 'md-rule'));
    else if (block.type === 'quote') { const q = el('blockquote', 'md-quote'); q.append(blocks(block.blocks, context)); fragment.append(q); }
    else if (block.type === 'list') {
      const listNode = el(block.ordered ? 'ol' : 'ul', 'md-list'); if (block.ordered && block.start !== 1) listNode.start = block.start;
      for (const item of block.items) { const li = el('li'); li.append(inline(item.children, context)); if (item.sub.length) li.append(blocks(item.sub, context)); listNode.append(li); }
      fragment.append(listNode);
    } else if (block.type === 'table') {
      const wrap = el('div', 'md-table-wrap'), table = el('table', 'md-table'), head = el('thead'), headRow = el('tr');
      block.head.forEach((cell, index) => { const th = el('th'); th.style.textAlign = block.align[index] || 'left'; th.append(inline(cell, context)); headRow.append(th); });
      head.append(headRow); table.append(head);
      const body = el('tbody');
      for (const row of block.rows) { const tr = el('tr'); row.forEach((cell, index) => { const td = el('td'); td.style.textAlign = block.align[index] || 'left'; td.append(inline(cell, context)); tr.append(td); }); body.append(tr); }
      table.append(body); wrap.append(table); fragment.append(wrap);
    } else if (block.type === 'code') {
      const wrap = el('div', 'md-codeblock'), bar = el('div', 'md-codebar'), copy = el('button', 'md-copy', 'Copy');
      copy.type = 'button';
      copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(block.text); copy.textContent = 'Copied'; setTimeout(() => { copy.textContent = 'Copy'; }, 1200); } catch {} });
      bar.append(el('span', 'md-lang', block.lang || 'code'), copy);
      const pre = el('pre'), code = el('code');
      for (const token of highlight(block.text)) code.append(token.type === 'plain' ? document.createTextNode(token.text) : el('span', 'tok-' + token.type, token.text));
      pre.append(code); wrap.append(bar, pre); fragment.append(wrap);
    }
  }
  return fragment;
}

/** A container with the reply rendered as Markdown. `context.openLink(url)` and `context.loadImage(path)` are optional. */
export function renderMarkdown(text, context = {}) {
  const node = el('div', 'md');
  node.append(blocks(parseMarkdown(text), context));
  return node;
}
