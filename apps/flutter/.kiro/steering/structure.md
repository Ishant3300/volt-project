# Project Structure

```
antigravity-awesome-skills/
├── skills/                    # 1000+ skill directories, each containing SKILL.md
│   └── {skill-name}/         # Kebab-case folder name must match frontmatter `name`
│       └── SKILL.md          # Required. YAML frontmatter + markdown instructions
├── scripts/                   # Build, validation, and maintenance tooling
│   ├── validate_skills.py     # Skill validation (frontmatter, structure, quality)
│   ├── validate-skills.js     # JS-based skill validation
│   ├── generate_index.py      # Generates skills_index.json from skills/
│   ├── build-catalog.js       # Builds CATALOG.md and data/catalog.json
│   ├── update_readme.py       # Updates README.md skill counts and tables
│   ├── run-python.js          # Python 3 bridge for npm scripts
│   ├── sync_microsoft_skills.py  # Syncs official Microsoft skills
│   └── tests/                 # Test suite (JS + Python)
├── lib/
│   └── skill-utils.js         # Shared utilities: frontmatter parsing, tokenization, skill reading
├── data/                      # Generated data files
│   ├── catalog.json           # Full skill catalog
│   ├── skills_index.json      # Skill index for search/web app
│   ├── bundles.json           # Bundle definitions
│   ├── workflows.json         # Workflow definitions
│   └── aliases.json           # Skill alias mappings
├── bin/
│   └── install.js             # npx CLI installer entry point
├── web-app/                   # React/Vite interactive skill browser
│   ├── src/                   # React components and app logic
│   └── public/                # Static assets including skills.json
├── docs/                      # Project documentation
│   ├── SKILL_ANATOMY.md       # How to write a SKILL.md
│   ├── QUALITY_BAR.md         # Validation standards and quality requirements
│   ├── BUNDLES.md             # Role-based skill bundles
│   ├── WORKFLOWS.md           # Step-by-step workflow playbooks
│   └── USAGE.md               # Post-install usage guide
├── .github/                   # CI/CD workflows, issue templates, PR template
├── CATALOG.md                 # Generated full skill catalog (markdown)
├── CONTRIBUTING.md            # Contribution guide
├── README.md                  # Main project README
└── package.json               # Root npm config with all build/validate scripts
```

## Key Conventions
- Each skill lives in `skills/{kebab-case-name}/SKILL.md`
- SKILL.md frontmatter requires: `name`, `description`, `risk` (none/safe/critical/offensive/unknown), `source`
- Optional frontmatter: `date_added`, `version`, `author`, `tags`
- Folder name must exactly match the `name` field in frontmatter
- Generated files (catalog.json, skills_index.json, CATALOG.md) are rebuilt via `npm run build`
- The `data/` directory holds machine-readable metadata; `docs/` holds human-readable guides
- Symlinks are used for some official skills (Windows users need Developer Mode or admin Git)
