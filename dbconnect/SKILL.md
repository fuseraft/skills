---
name: dbconnect
description: Use dbconnect.exe to validate connectivity, inspect schema, run SQL files including migration scripts, and export results. Keep invocation specifics in references/ and execute through scripts/ wrappers.
---

# dbconnect

## When to use
- Need to test SQL Server or Oracle connectivity.
- Need to list named connections from a `.connections` file.
- Need to inspect schema or run ad hoc SQL.
- Need to execute SQL files such as migrations.
- Need query output written to CSV.

## Inputs to gather
- Target DB type: `mssql` or `oracle`
- Either `--conn` string or named connection for `--use`
- SQL text or path to `.sql` file
- Optional CSV output path

## Procedure
1. Read `references/dbconnect-usage.md` and `references/dbconnect-examples.md`.
2. Confirm `dbconnect\bin\dbconnect.exe` exists.
3. If the user wants saved connections, run `scripts\dbconnect-list.bat`.
4. For a connectivity check, run a trivial query like `SELECT 1` using the right wrapper.
5. For schema inspection, use the schema query pattern in `references/dbconnect-examples.md`.
6. For migrations or other file-based SQL, execute the `.sql` file path through the wrapper.
7. If results must be preserved, pass an output CSV path.
8. Return the exact command run, summarize results, and call out any prerequisite failures.

## Rules
- Prefer wrapper scripts in `scripts/`; do not invoke the exe manually unless troubleshooting.
- Do not invent connection strings, named connections, or schema names.
- Treat destructive SQL as dangerous; require explicit user intent before running it.
- If authentication or network access fails, report the exact stderr and stop.
- Keep secrets out of logs and responses when echoing commands.

## References
- `references/dbconnect-usage.md`
- `references/dbconnect-examples.md`
- `scripts/dbconnect-run.ps1`
- `scripts/dbconnect-run.bat`
- `scripts/dbconnect-list.bat`
