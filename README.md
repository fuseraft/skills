# Skills Repository

This repository contains reusable skills for database operations and other workflows.

## Contents

### dbconnect Skill

A skill for database connectivity testing, schema inspection, and SQL execution using the dbconnect CLI tool.

**Location:** `dbconnect/`

**Key Features:**
- Test SQL Server or Oracle connectivity
- List named database connections
- Inspect database schema
- Execute SQL files including migrations
- Export query results to CSV

**Structure:**
- `SKILL.md` - The skill definition and procedure
- `references/` - Usage documentation and examples
- `scripts/` - PowerShell and batch wrapper scripts
- `dbconnect/` - The dbconnect CLI tool source code

**Quick Start:**

Build the dbconnect tool:
```powershell
cd dbconnect/dbconnect
.\build.ps1
```

For detailed usage, see:
- [dbconnect CLI README](dbconnect/dbconnect/README.md) - Full CLI documentation
- [dbconnect SKILL.md](dbconnect/SKILL.md) - Skill usage instructions

### build-docx Skill

Generates a DOCX file from structured content, a template, or a description — detects the project stack, picks the right library, and writes a self-contained builder script.

**Location:** `build-docx/`

**Key Features:**
- Detect the project's language/stack and recommend the right library (`python-docx`, `docx` npm, or `DocumentFormat.OpenXml`/`DocX`)
- Generate documents from a Markdown file, JSON/structured data, or a free-form description
- Clone an existing DOCX template and fill in `{{placeholders}}`
- Build tables, images, headings, and styled sections programmatically

**Structure:**
- `SKILL.md` - The skill definition and procedure
- `references/` - Pattern references per library (`python-docx`, `docx` npm, `DocumentFormat.OpenXml`)
- `scripts/detect_docx_stack.py` - Stack detection helper

**Quick Start:**

Detect the project's stack and recommended library:
```bash
python3 build-docx/scripts/detect_docx_stack.py <project-root>
```

For detailed usage, see:
- [build-docx SKILL.md](build-docx/SKILL.md) - Full workflow and library pattern references

### sandbox-test Skill

Builds and runs a throwaway harness in the project's own stack to verify logic before modifying production code. Supports .NET, Go, Rust, Python, TypeScript, Node.js, and Java.

**Location:** `sandbox-test/`

**Key Features:**
- Detect the project's stack and its scaffold/build/run/cleanup commands
- Scaffold a minimal, disposable harness instead of touching production files
- Instrument with labeled `[DBG]` debug output at every meaningful boundary
- Iterate up to 5 times before stopping to report findings and ask for guidance

**Structure:**
- `SKILL.md` - The skill definition and procedure
- `references/stack-patterns.md` - Detection markers, scaffold/build/run/debug patterns per stack
- `scripts/detect_stack.py` - Stack detection helper

**Quick Start:**

Detect the project's stack:
```bash
python3 sandbox-test/scripts/detect_stack.py <project-root>
```

For detailed usage, see:
- [sandbox-test SKILL.md](sandbox-test/SKILL.md) - Full workflow

### commit Skill

Stages and commits changes using the conventional commit format (`type: description`, imperative mood, staged files named explicitly — never `git add -A`).

**Location:** `commit/`

**Key Features:**
- Enforces `type: description` subject lines (≤ 72 characters, imperative mood, no trailing period)
- Writes a body only when the change is non-trivial, explaining *why* rather than restating the diff
- Stages only the files that belong to the change — never `git add -A` or `git add .`
- Verifies the resulting commit before reporting it back

**Structure:**
- `SKILL.md` - The skill definition and procedure

**Quick Start:**

No setup required — apply the skill whenever a commit is needed, starting from:
```bash
git status --short && git diff HEAD
```

For detailed usage, see:
- [commit SKILL.md](commit/SKILL.md) - Full workflow and commit-type table

### datamap Skill

Maps data flow through a C# codebase from source (executed SQL via ADO.NET/Dapper, API calls, files) to destination (database tables, API endpoints, files on disk/SFTP/SharePoint, email). Produces a validated JSONL data map and converts it to a deterministic CSV.

**Location:** `datamap/`

**Key Features:**
- Detect SQL (ADO.NET/Dapper), API calls, and file I/O as sources; databases, APIs, files, and email as destinations — Entity Framework is explicitly out of scope since its generated SQL isn't statically visible
- Four-pass workflow: generate structural JSONL, validate, annotate `notes`, validate again, convert to CSV
- Deterministic output: schema validation rejects blank required fields, CSV conversion is RFC 4180-quoted with a fixed column order
- All read/validate/write operations go through PowerShell scripts rather than hand-edited JSONL

**Structure:**
- `SKILL.md` - The four-pass workflow (generate → validate → annotate → validate → convert)
- `references/` - Schema conventions, C# detection patterns (ADO.NET/Dapper/HttpClient/EPPlus/SSH.NET/Graph/etc.), notes-writing guidance, and a full worked example
- `scripts/` - PowerShell 5.1-compatible scripts to append, validate, annotate, and convert the datamap

**Quick Start:**

Generate, validate, and convert a datamap:
```powershell
pwsh -File datamap/scripts/New-DataMapEntry.ps1 -Path datamap.jsonl -FromJson rows.json
pwsh -File datamap/scripts/Test-DataMapJsonl.ps1 -Path datamap.jsonl
pwsh -File datamap/scripts/ConvertTo-DataMapCsv.ps1 -JsonlPath datamap.jsonl -CsvPath datamap.csv
```

For detailed usage, see:
- [datamap SKILL.md](datamap/SKILL.md) - Full four-pass workflow
- [datamap schema reference](datamap/references/schema.md) - Field conventions and sentinel values

## Development

Each skill follows the structure:
- **SKILL.md** - Skill metadata, triggers, procedure, and rules
- **references/** - Supporting documentation
- **scripts/** - Executable wrappers and helper scripts
