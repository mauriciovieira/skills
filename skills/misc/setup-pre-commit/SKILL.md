---
name: setup-pre-commit
description: Set up Husky pre-commit hooks with lint-staged (Biome), type checking, and tests in the current repo. Use when user wants to add pre-commit hooks, set up Husky, configure lint-staged, or add commit-time formatting/linting/typechecking/testing.
---

# Setup Pre-Commit Hooks

## What This Sets Up

- **Husky** pre-commit hook
- **lint-staged** running Biome on all staged files
- **Biome** config (if missing) — formatter + linter, replaces Prettier + ESLint
- **typecheck** and **test** scripts in the pre-commit hook

## Steps

### 1. Detect package manager

Check for `package-lock.json` (npm), `pnpm-lock.yaml` (pnpm), `yarn.lock` (yarn), `bun.lockb` (bun). Use whichever is present. Default to npm if unclear.

### 2. Install dependencies

Install as devDependencies:

```
husky lint-staged @biomejs/biome
```

### 3. Initialize Husky

```bash
npx husky init
```

This creates `.husky/` dir and adds `prepare: "husky"` to package.json.

### 4. Create `.husky/pre-commit`

Write this file (no shebang needed for Husky v9+):

```
npx lint-staged
npm run typecheck
npm run test
```

**Adapt**: Replace `npm` with detected package manager. If repo has no `typecheck` or `test` script in package.json, omit those lines and tell the user.

### 5. Create `.lintstagedrc`

```json
{
  "*": "biome check --write --no-errors-on-unmatched"
}
```

`biome check` formats **and** lints. `--write` applies safe fixes; `--no-errors-on-unmatched` stops Biome erroring when a staged file isn't a type it handles (images, etc.).

### 6. Create `biome.json` (if missing)

Only create if no Biome config exists (`biome.json` or `biome.jsonc`). Use these defaults:

```json
{
  "$schema": "https://biomejs.dev/schemas/2.0.0/schema.json",
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 80
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "trailingCommas": "es5",
      "semicolons": "always",
      "arrowParentheses": "always"
    }
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "assist": {
    "actions": {
      "source": {
        "organizeImports": "on"
      }
    }
  }
}
```

**Pin the `$schema` version** to the installed Biome version (check `npx biome --version`) so the config matches the binary.

### 7. Verify

- [ ] `.husky/pre-commit` exists and is executable
- [ ] `.lintstagedrc` exists
- [ ] `prepare` script in package.json is `"husky"`
- [ ] `biome.json` config exists
- [ ] Run `npx lint-staged` to verify it works

### 8. Commit

Stage all changed/created files and commit with message: `Add pre-commit hooks (husky + lint-staged + biome)`

This will run through the new pre-commit hooks — a good smoke test that everything works.

## Notes

- Husky v9+ doesn't need shebangs in hook files
- `biome check` does formatting and linting in one pass — no separate Prettier/ESLint steps
- `--no-errors-on-unmatched` skips files Biome can't handle (images, etc.) instead of failing the commit
- The pre-commit runs lint-staged first (fast, staged-only), then full typecheck and tests
