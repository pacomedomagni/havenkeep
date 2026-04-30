// Test-time stub for @scure/base. It's only reached transitively through
// the otplib chain, which we've already stubbed. This exists so any
// stray `import { something } from '@scure/base'` (in a test or in a
// mock helper) resolves cleanly instead of hitting the package's ESM
// `export` syntax.
const noop = {
  encode: (input) => Buffer.from(input).toString('hex'),
  decode: (input) => Buffer.from(input, 'hex'),
};

module.exports = {
  base32: noop,
  base64: noop,
  base16: noop,
  utils: { radix2: () => ({ encode: () => '', decode: () => new Uint8Array() }) },
};
