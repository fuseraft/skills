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

Generates a DOCX file from structured content, a template, or a description — detects the project stack, picks the right library (`python-docx`, `docx` npm, or `DocumentFormat.OpenXml`/`DocX`), and writes a self-contained builder script.

**Location:** `build-docx/`

### sandbox-test Skill

Builds and runs a throwaway harness in the project's own stack to verify logic before modifying production code. Supports .NET, Go, Rust, Python, TypeScript, Node.js, and Java.

**Location:** `sandbox-test/`

### commit Skill

Stages and commits changes using the conventional commit format (`type: description`, imperative mood, staged files named explicitly — never `git add -A`).

**Location:** `commit/`

### datamap Skill

Maps data flow through a C# codebase from source (executed SQL via ADO.NET/Dapper, API calls, files) to destination (database tables, API endpoints, files on disk/SFTP/SharePoint, email). Produces a validated JSONL data map (structure first, then annotated with transformation notes) and converts it to a deterministic CSV. Entity Framework is out of scope as a SQL source since its generated SQL isn't statically visible.

**Location:** `datamap/`

**Structure:**
- `SKILL.md` - The four-pass workflow (generate → validate → annotate → validate → convert)
- `references/` - Schema conventions, C# detection patterns (ADO.NET/Dapper/HttpClient/EPPlus/SSH.NET/Graph/etc.), notes-writing guidance, and a full worked example
- `scripts/` - PowerShell 5.1-compatible scripts to append, validate, annotate, and convert the datamap without hand-editing JSONL

## Development

Each skill follows the structure:
- **SKILL.md** - Skill metadata, triggers, procedure, and rules
- **references/** - Supporting documentation
- **scripts/** - Executable wrappers and helper scripts
