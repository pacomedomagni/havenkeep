// Shared rate-limiter mock for the test suite. Every test file used to
// inline its own copy of this object, which meant adding a new limiter
// to middleware/rateLimiter.ts silently broke every test (the inline
// mocks didn't export the new symbol → routes mounted with `undefined`
// → Express crashed at module load with "Route.post() requires a
// callback function").
//
// Centralizing here means: add a new limiter to middleware/rateLimiter.ts
// AND extend the export below. Test files import via:
//   jest.mock('../middleware/rateLimiter', () => require('./test-rate-limiter-mock'));

const pass = (_req: any, _res: any, next: any) => next();

module.exports = {
  __esModule: true,
  // Auth + session
  authRateLimiter: pass,
  loginPerEmailRateLimiter: pass,
  refreshRateLimiter: pass,
  passwordResetRateLimiter: pass,
  passwordChangeRateLimiter: pass,
  changeEmailRateLimiter: pass,
  // Endpoint families
  uploadRateLimiter: pass,
  activationCodeRateLimiter: pass,
  verifyPremiumRateLimiter: pass,
  writeRateLimiter: pass,
  giftResendRateLimiter: pass,
  receiptScanRateLimiter: pass,
  newsletterRateLimiter: pass,
  contactRateLimiter: pass,
  itemsListRateLimiter: pass,
  csvExportRateLimiter: pass,
  readRateLimiter: pass,
  emailScannerScanRateLimiter: pass,
  emailScannerWriteRateLimiter: pass,
  // Lifecycle
  initializeRateLimiter: jest.fn().mockResolvedValue(undefined),
  initializeEndpointRedis: jest.fn().mockResolvedValue(undefined),
  shutdownRateLimiter: jest.fn().mockResolvedValue(undefined),
  closeRateLimiterRedis: jest.fn().mockResolvedValue(undefined),
};
