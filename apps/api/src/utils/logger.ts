import pino from 'pino';
import { config } from '../config';

export const logger = pino({
  level: config.env === 'production' ? 'info' : 'debug',
  // Use pino-pretty for development, JSON for production (Loki)
  transport: config.env === 'development' ? {
    target: 'pino-pretty',
    options: {
      colorize: true,
      translateTime: 'SYS:standard',
      ignore: 'pid,hostname',
    }
  } : undefined,
  // Production: JSON output for Loki/Promtail ingestion
  formatters: config.env === 'production' ? {
    level: (label) => {
      return { level: label };
    },
  } : undefined,
  base: {
    service: 'havenkeep-api',
    environment: config.env,
  },
});
