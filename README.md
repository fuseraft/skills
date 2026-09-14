# Skills Repository

This repository contains reusable, project-agnostic skills for the fuseraft Agent Skills ecosystem — database operations, document generation, commits, sandboxed experimentation, data-flow mapping, and more.

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
- `scripts/detect_docx_stack.ps1` - Stack detection helper

**Quick Start:**

Detect the project's stack and recommended library:
```powershell
pwsh -File build-docx/scripts/detect_docx_stack.ps1 <project-root>
```

For detailed usage, see:
- [build-docx SKILL.md](build-docx/SKILL.md) - Full workflow and library pattern references

### sandbox-test Skill

Builds and runs a throwaway .NET console harness to verify logic before modifying production code. .NET-specific by design.

**Location:** `sandbox-test/`

**Key Features:**
- Detect a .NET project (`*.csproj`, `*.sln`, `global.json`, `Directory.Build.props`) and report its scaffold/build/run/cleanup commands
- Scaffold a minimal, disposable `dotnet new console` harness instead of touching production files
- Instrument with labeled `[DBG]` debug output at every meaningful boundary
- Iterate up to 5 times before stopping to report findings and ask for guidance

**Structure:**
- `SKILL.md` - The skill definition and procedure
- `references/stack-patterns.md` - .NET detection markers, scaffold/build/run/debug patterns
- `scripts/detect_stack.ps1` - .NET project detection helper

**Quick Start:**

Confirm the project is .NET and get its harness commands:
```powershell
pwsh -File sandbox-test/scripts/detect_stack.ps1 <project-root>
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

### terminal-screenshot Skill

Captures a real screenshot of an actual terminal application running real commands — not an HTML/CSS mockup — on an isolated virtual display that never touches the user's real desktop or real settings. Linux/X11 only.

**Location:** `terminal-screenshot/`

**Key Features:**
- Runs the terminal emulator on an isolated Xvfb display, forced off Wayland (`GDK_BACKEND=x11`) so it can't render on the user's real desktop
- Never uses `gsettings`/`dconf` to theme the session (that routes through the shared D-Bus bus and mutates the user's real app settings); colors are set at runtime only via OSC escape sequences
- Drives real content into the visible session via `tmux send-keys`, polling for a clean prompt instead of guessing sleep durations
- Full teardown-and-reverify checklist, including the sandbox's habit of silently reaping detached background processes between steps

**Structure:**
- `SKILL.md` - Critical safety rules plus the full capture/crop/cleanup workflow

**Quick Start:**

No setup required — read the two Critical Safety Rules first, then follow the numbered workflow starting from:
```bash
for c in tilix xterm kitty alacritty gnome-terminal konsole foot wezterm; do command -v "$c" && break; done
```

For detailed usage, see:
- [terminal-screenshot SKILL.md](terminal-screenshot/SKILL.md) - Full workflow and both safety rules

## Development

Each skill follows the structure:
- **SKILL.md** - Skill metadata, triggers, procedure, and rules
- **references/** - Supporting documentation
- **scripts/** - Executable wrappers and helper scripts
