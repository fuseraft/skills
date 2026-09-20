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

Converts GitHub-flavored Markdown to a Word document with a single bundled, schema-validated converter (Markdig + the OpenXML SDK). Requires the .NET 10 SDK.

**Location:** `build-docx/`

**Key Features:**
- Headings map to real Word *Heading* styles, and `#anchor` links jump to them
- Nested/ordered/lettered/task lists with real Word numbering, block quotes, GitHub alerts, footnotes
- Pipe and grid tables (alignment, repeating header row, colspan/rowspan), code blocks, images (PNG/JPEG/GIF/BMP, scaled to the page)
- A safe subset of raw HTML; anything that can't be rendered produces a `warning:` instead of vanishing
- Output is validated against the OpenXML schema and written atomically; local images are confined to an image root

**Structure:**
- `SKILL.md` - The skill definition, supported Markdown, and known degradations
- `scripts/md2docx.cs` - The converter (a single-file .NET app)

**Quick Start:**

```bash
dotnet run build-docx/scripts/md2docx.cs -- report.md report.docx
```

For detailed usage, see:
- [build-docx SKILL.md](build-docx/SKILL.md) - Options, exit codes, supported Markdown, and degradations

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

### azure-devops Skill

Work items, pull requests, repositories, and pipelines in Azure DevOps through a shared set of Python scripts. Works against both Azure DevOps Services and on-prem Azure DevOps Server, choosing between the `az` CLI and direct REST calls per operation.

**Location:** `azure-devops/`

**Key Features:**
- Work items: create (with acceptance criteria), get, query, update fields/state, comment, list comments, delete
- Pull requests: list, get, and comment; repositories: list and code search
- Pipelines: list and filter runs by pipeline, branch, state, and result
- Consistent `--backend auto|cli|rest` selection, with REST as the dependable path for on-prem collections
- Configured through `ADO_URL`, `ADO_PROJECT`, `ADO_PAT`, and optional `ADO_REPO`

**Structure:**
- `SKILL.md` - The skill definition, environment contract, and backend strategy
- `README.md` - Script usage and examples
- `references/` - Per-area script references (work items, pull requests, repositories, pipelines, foundation)
- `scripts/` - The Python scripts and their shared `_ado_common.py`

**Quick Start:**

Check the environment and CLI/REST prerequisites:
```bash
python3 azure-devops/scripts/check-ado-prereqs.py
```

For detailed usage, see:
- [azure-devops SKILL.md](azure-devops/SKILL.md) - Scope, environment, and backend strategy
- [azure-devops README](azure-devops/README.md) - Script usage and examples

## Development

Each skill follows the structure:
- **SKILL.md** - Skill metadata, triggers, procedure, and rules
- **references/** - Supporting documentation
- **scripts/** - Executable wrappers and helper scripts
