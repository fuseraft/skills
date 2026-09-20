# dbconnect usage reference

Binary:
- `dbconnect\bin\dbconnect.exe`

Flags verified from `dbconnect/README.md`:
- `--help` print help text
- `--oracle` connect to Oracle using Kerberos
- `--conn <connection-string>` use an explicit connection string
- `--use <name>` use a named connection from a `<NAME>.connections` JSON file
- `--list` list available named connections
- `--sql "..."` execute inline SQL text
- `--sql <file>` execute SQL from a file
- `--output <file>` write results to a file: CSV by default, JSON with `--format json`
- `--format <table|json>` output format, default `table`
- `--max-rows <n>` cap console output (table or JSON) at `n` rows, default 200 (does not limit `--output` exports)
- `--timeout <seconds>` command timeout applied to each SQL batch; `0` means no timeout, omitted uses the database driver's default
- `--allow-write` required to run INSERT/UPDATE/DELETE/MERGE/DROP/ALTER/CREATE/TRUNCATE/GRANT/REVOKE/EXEC/EXECUTE statements

Connection file format:
- File name pattern: `<NAME>.connections`
- JSON shape: `{ "connections": [{ "name": "...", "connectionstring": "...", "type": "oracle|mssql" }] }`

Notes:
- SQL Server examples in the README use `Trusted_Connection=yes;TrustServerCertificate=true;`
- Oracle examples use `--oracle` plus a connection string containing `User Id=/;TNS_ADMIN=...`
- `dbconnect` can inspect schema, run ad hoc queries, and execute migration-style `.sql` files via `--sql <file>`
- For SQL Server (`--sql <file>`), input is split on lines that contain only `GO` and each batch runs sequentially against the same connection — needed because raw ADO.NET commands can't execute `GO` batch separators directly. Only the last batch that returns rows is printed or exported.
- Console table output is capped at `--max-rows` (default 200) to avoid flooding the caller with huge result sets; a truncation notice is printed when more rows exist. Pass `--output <file>` to export the full result set instead — file exports ignore the cap.
- `--format json` prints (or, with `--output`, writes) `{ "rowCount": n, "truncated": bool, "rows": [ { "<column>": <value>, ... } ] }`. On the console the cap still applies and is reported through `truncated` instead of a printed notice. With `--output` and `--format json` the file is JSON, not CSV.
- `--timeout` is a per-batch command timeout, so a script with several `GO` batches can run longer overall. A negative value, or a `--format` other than `table` or `json`, is rejected as an argument error (exit code 2).
- Without `--allow-write`, dbconnect scans every batch (after stripping comments and string/quoted-identifier literals) for INSERT/UPDATE/DELETE/MERGE/DROP/ALTER/CREATE/TRUNCATE/GRANT/REVOKE/EXEC/EXECUTE keywords and refuses to open a connection if any are found, exiting with code 7. This is a best-effort text scan, not a parser — it can still misfire on unusual SQL (e.g. a keyword inside a comment-stripping edge case). Always confirm with the user before adding `--allow-write`.
- Exit codes: `0` success, `1` unexpected error, `2` argument error, `3` file not found, `4` database error, `5` I/O error, `6` configuration error, `7` write blocked (missing `--allow-write`).
