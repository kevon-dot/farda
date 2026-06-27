## About

This project was created with [express-generator-typescript](https://github.com/seanpmaxwell/express-generator-typescript).

This package uses **pnpm** as its package manager (see `packageManager` in
`package.json`) and **Biome** for linting/formatting. Use `pnpm <script>`
rather than `npm <script>`.

## Documentation

- [API Documentation](./API_DOCUMENTATION.md) - Detailed API endpoints, request bodies, and parameters.

## Available Scripts

### `pnpm dev` (hot reloading)

Run the server in development mode.<br/>

**IMPORTANT** development mode uses `tsx` for performance reasons which DOES NOT check for typescript errors. Run `pnpm type-check` to check for type errors. NOTE: you should use your IDE to prevent most type errors.

### `pnpm test`

Run unit-tests with <a href="https://vitest.dev/guide/">vitest</a>.

### `pnpm lint` / `pnpm lint:fix`

Check for (or auto-fix) lint/format issues with [Biome](https://biomejs.dev/).

### `pnpm build`

Type-check and build the project for production (`tsc --project tsconfig.prod.json`).

### `pnpm start`

Run the production build (must be built first).

### `pnpm type-check`

Check for typescript errors without emitting.
