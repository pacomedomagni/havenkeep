// Test-time stub for the otplib plugin packages. They're constructor
// classes that the real OTP wires together; the stubbed OTP class
// in otplib.cjs ignores them, so the no-op here just exposes the
// constructors with the expected names.
class NobleCryptoPlugin {}
class ScureBase32Plugin {}

module.exports = {
  NobleCryptoPlugin,
  ScureBase32Plugin,
};
