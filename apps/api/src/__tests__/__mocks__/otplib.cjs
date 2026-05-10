// Test-time stub for otplib. mfa.service.ts loads this through the Jest
// moduleNameMapper. The default behaviour (`verifySync` always returns
// {valid:true}) is fine for tests that don't care about TOTP correctness
// — they just need MFA-typed shapes to compile and run.
//
// H20: mfa.test.ts needs to distinguish "right code" from "wrong code".
// Use `__setExpectedToken(value)` to make verifySync only accept that
// exact value; reset with `__setExpectedToken(null)` for the next suite.

let _expectedToken = null;
function __setExpectedToken(value) {
  _expectedToken = value;
}

class OTP {
  constructor(_opts) {}
  generateSecret() {
    return 'JBSWY3DPEHPK3PXP'; // canonical RFC 6238 example secret
  }
  generateURI({ issuer, label, secret }) {
    return `otpauth://totp/${encodeURIComponent(label)}?secret=${secret}&issuer=${encodeURIComponent(issuer)}`;
  }
  verifySync({ token }) {
    if (_expectedToken === null) return { valid: true };
    return { valid: token === _expectedToken };
  }
}

module.exports = { OTP, __setExpectedToken };
