/**
 * Server-side configuration. API_URL must be set via environment variable.
 * Falls back to localhost only for local development.
 */
export const API_URL = process.env.API_URL || 'http://localhost:3000';
