import sharp from 'sharp';

// 1.2: shared sharp configuration. Pre-1.2 the cache(false) +
// concurrency(1) calls only ran when documents.ts was the first
// importer; uploads.ts and receipts.ts loaded sharp on their own with
// the defaults. Centralising here means every consumer inherits the
// safe defaults whether or not documents.ts is loaded first.
//
// `limitInputPixels: SHARP_PIXEL_LIMIT` is also intended to be passed
// to every `sharp(buffer, …)` call so a 16384×16384 PNG that
// decompresses to ~1GB RGBA is rejected before sharp tries to allocate.
//
// failOn: 'error' makes sharp abort on truncated/invalid streams
// rather than try to read what it can — important for uploads where
// the user could send a partial bomb.

sharp.cache(false);
sharp.concurrency(1);

/** 100M pixels (10kx10k). Anything larger is rejected before decode. */
export const SHARP_PIXEL_LIMIT = 100_000_000;

/** Default options for every sharp() call on user-supplied bytes. */
export const SHARP_INPUT_OPTIONS: sharp.SharpOptions = {
  limitInputPixels: SHARP_PIXEL_LIMIT,
  failOn: 'error',
};
