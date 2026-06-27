import path from 'path';
import { defineConfig } from 'vitest/config';

// Self-contained unit-test config: no DB/server bootstrap. Pure-function tests
// only, so the suite runs in CI without Postgres or live credentials.
const config = defineConfig({
  test: {
    globals: true,
    environment: 'node',
    isolate: true,
    include: ['tests/**/*.test.ts'],
  },
  resolve: {
    alias: {
      '@src': path.resolve(__dirname, './src'),
    },
  },
});

export default config;
