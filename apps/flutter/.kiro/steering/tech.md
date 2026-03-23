# Tech Stack & Build System

## Core Tooling (Root)
- Node.js (CommonJS) — scripts, validation, catalog generation, CLI installer
- Python 3 — skill validation, index generation, README updates, metadata management
- YAML frontmatter — every skill uses YAML frontmatter in SKILL.md for metadata
- `yaml` npm package (v2.x) — YAML parsing in JS scripts
- `pyyaml` — YAML parsing in Python scripts

## Web App (`web-app/`)
- React 19 with TypeScript
- Vite 7 (build tool and dev server)
- Tailwind CSS 4 (via PostCSS)
- Vitest (testing)
- ESLint 9 (linting)
- Key libraries: react-router-dom, react-markdown, framer-motion, lucide-react, highlight.js, react-virtuoso, Supabase client

## Python Bridge
- `scripts/run-python.js` wraps all Python script invocations, auto-detecting `python3`, `python`, or `py -3`
- Override with `ANTIGRAVITY_PYTHON` or `npm_config_python` env vars

## Common Commands

```bash
# Validate all skills (soft mode)
npm run validate

# Validate all skills (strict/CI mode)
npm run validate:strict

# Generate skills index
npm run index

# Update README with current skill counts
npm run readme

# Full pipeline: validate → index → readme
npm run chain

# Build catalog (JSON + markdown)
npm run catalog

# Full build: chain + catalog
npm run build

# Run tests (local only)
npm run test
npm run test:local

# Run tests including network tests
ENABLE_NETWORK_TESTS=1 npm run test
npm run test:network

# Web app dev server
npm run app:dev

# Web app production build
npm run app:build

# Sync Microsoft official skills
npm run sync:microsoft
```

## Testing
- Test runner: `scripts/tests/run-test-suite.js` (custom Node.js runner, not a framework)
- Local tests: heading validation (JS + Python)
- Network tests: Microsoft repo inspection, comprehensive coverage (gated behind `ENABLE_NETWORK_TESTS=1`)
- Web app tests: Vitest with React Testing Library and jsdom
