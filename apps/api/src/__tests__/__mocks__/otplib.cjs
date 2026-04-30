// Test-time stub for otplib. mfa.service.ts loads this through the Jest
// moduleNameMapper. None of the test suites exercise TOTP enrollment
// directly — auth tests use the email+password path — so the stub is
// shape-only: enough to satisfy `new OTP({...}).method(...)` calls.
//
// If a future test needs real TOTP behavior, mock it per-test with
// `jest.mock('otplib', () => ({...}))` instead of removing this stub
// (every other suite would then fail to load, since @scure/base's ESM
// syntax still trips Jest).
class OTP {
  constructor(_opts) {}
  generateSecret() {
    return 'JBSWY3DPEHPK3PXP'; // canonical RFC 6238 example secret
  }
  generateURI({ issuer, label, secret }) {
    return `otpauth://totp/${encodeURIComponent(label)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`;
  }
  verifySync(_args) {
    return { valid: true };
  }
}

module.exports = { OTP };
