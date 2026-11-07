'use strict';
// Reads the text of a PDF, one string per page, with Mozilla's pdf.js (no native code, nothing leaves this PC).
let library;
async function load() { return library ||= await import('pdfjs-dist/legacy/build/pdf.mjs'); }

/** @param {Uint8Array|Buffer} bytes */
async function pdfPages(bytes, { maxPages = 400 } = {}) {
  const pdfjs = await load();
  const document = await pdfjs.getDocument({ data: new Uint8Array(bytes), useSystemFonts: true, disableFontFace: true, isEvalSupported: false, verbosity: 0 }).promise;
  try {
    const pages = [];
    for (let number = 1; number <= Math.min(document.numPages, maxPages); number++) {
      const page = await document.getPage(number);
      const content = await page.getTextContent();
      pages.push(content.items.map(item => item.str + (item.hasEOL ? '\n' : ' ')).join('').replace(/[ \t]+/g, ' ').trim());
      page.cleanup();
    }
    return pages;
  } finally { await document.destroy(); }
}
module.exports = { pdfPages };
