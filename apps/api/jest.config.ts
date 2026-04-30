import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  // The __mocks__/ subdir holds CJS stubs (Stripe, otplib, @scure/base)
  // that the test suites import via moduleNameMapper. They have no
  // tests; explicitly skip them so Jest doesn't surface "Your test
  // suite must contain at least one test" failures.
  testPathIgnorePatterns: ['/node_modules/', '/__mocks__/'],
  maxWorkers: 1,
  setupFilesAfterEnv: ['./src/__tests__/setup.ts'],
  testTimeout: 15000,
  moduleFileExtensions: ['ts', 'js', 'json'],
  // The TOTP MFA stack (mfa.service.ts → otplib → @otplib/plugin-base32-scure
  // → @scure/base) is pure-ESM. Jest's resolver picks up @scure/base's
  // `index.js` containing `export const utils = ...` and chokes.
  //
  // Our tests don't exercise MFA — auth flows are smoke-tested via direct
  // login/register. We stub @scure/base + the otplib chain to no-op
  // implementations for the test environment. Run-time (tsx for dev,
  // node for prod) is unaffected; the real packages load there.
  moduleNameMapper: {
    '^@scure/base$': '<rootDir>/src/__tests__/__mocks__/scure-base.cjs',
    '^otplib$': '<rootDir>/src/__tests__/__mocks__/otplib.cjs',
    '^@otplib/plugin-crypto-noble$': '<rootDir>/src/__tests__/__mocks__/otplib-noop.cjs',
    '^@otplib/plugin-base32-scure$': '<rootDir>/src/__tests__/__mocks__/otplib-noop.cjs',
  },
};

export default config;
