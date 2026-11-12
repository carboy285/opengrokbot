// Loaded before anything else in the engine. WebKit (the Mac app's hidden web view) cannot iterate a
// ReadableStream with `for await`, which the phonemizer Kokoro uses does while it starts. Without this the
// engine failed to load on the Mac ("undefined is not a function … _ of M").
if (typeof ReadableStream !== 'undefined' && !ReadableStream.prototype[Symbol.asyncIterator]) {
  ReadableStream.prototype[Symbol.asyncIterator] = async function* () {
    const reader = this.getReader();
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) return;
        yield value;
      }
    } finally { reader.releaseLock(); }
  };
}
