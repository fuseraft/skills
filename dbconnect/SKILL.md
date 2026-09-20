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
- Need query output written to CSV or JSON.

## Inputs to gather
- Target DB type: `mssql` or `oracle`
- Either `--conn` string or named connection for `--use`
- SQL text or path to `.sql` file
- Optional output path (CSV by default, or JSON with `--format json`)
- Optional `--format json` when another tool will parse the results, and `--timeout <seconds>` for long-running queries (`0` disables the timeout; omitted uses the driver default)
- Whether the SQL writes data (INSERT/UPDATE/DELETE/MERGE/DDL/EXEC) — if so, confirm intent with the user before adding `--allow-write`

## Procedure
1. Read `references/dbconnect-usage.md` and `references/dbconnect-examples.md`.
2. Confirm `dbconnect\bin\dbconnect.exe` exists.
3. If the user wants saved connections, run `scripts\dbconnect-list.bat`.
4. For a connectivity check, run a trivial query like `SELECT 1` using the right wrapper.
5. For schema inspection, use the schema query pattern in `references/dbconnect-examples.md`.
6. For migrations or other file-based SQL, execute the `.sql` file path through the wrapper. SQL Server files may contain `GO` batch separators; dbconnect splits and runs them as separate batches automatically.
7. If results must be preserved, pass an output path (CSV by default, JSON with `--format json`) — this also bypasses the console `--max-rows` cap. For large ad hoc queries without `--output`, either add `--max-rows <n>` or expect console output truncated at 200 rows by default; with `--format json` the truncation is reported as `"truncated": true` rather than a printed notice.
8. Return the exact command run, summarize results, and call out any prerequisite failures.

## Rules
- Prefer wrapper scripts in `scripts/`; do not invoke the exe manually unless troubleshooting.
- Do not invent connection strings, named connections, or schema names.
- dbconnect blocks INSERT/UPDATE/DELETE/MERGE/DROP/ALTER/CREATE/TRUNCATE/GRANT/REVOKE/EXEC/EXECUTE statements by default (exit code 7). Confirm explicit user intent before re-running with `--allow-write` — this is a text-based guard, not a parser, so do not treat its absence of a block as proof the SQL is safe.
- If authentication or network access fails, report the exact stderr and stop.
- Keep secrets out of logs and responses when echoing commands.

## References
- `references/dbconnect-usage.md`
- `references/dbconnect-examples.md`
- `scripts/dbconnect-run.ps1`
- `scripts/dbconnect-run.bat`
- `scripts/dbconnect-list.bat`
