import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts'],
  maxWorkers: 1,
  setupFilesAfterEnv: ['./src/__tests__/setup.ts'],
  testTimeout: 15000,
  moduleFileExtensions: ['ts', 'js', 'json'],
};

export default config;
