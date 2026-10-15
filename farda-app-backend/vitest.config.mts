import path from 'path';
import { defineConfig } from 'vitest/config';

// Database integration files share one disposable schema and some process env.
// Keep files isolated from each other; explicit concurrent-write cases within a
// file still run against native PostgreSQL in CI.
const config = defineConfig({
  test: {
    globals: true,
    environment: 'node',
    isolate: true,
    fileParallelism: false,
    include: ['tests/**/*.test.ts'],
  },
  resolve: {
    alias: {
      '@src': path.resolve(__dirname, './src'),
    },
  },
});

export default config;
