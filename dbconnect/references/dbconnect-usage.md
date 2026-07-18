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
- `--output <file>` write results to CSV

Connection file format:
- File name pattern: `<NAME>.connections`
- JSON shape: `{ "connections": [{ "name": "...", "connectionstring": "...", "type": "oracle|mssql" }] }`

Notes:
- SQL Server examples in the README use `Trusted_Connection=yes;TrustServerCertificate=true;`
- Oracle examples use `--oracle` plus a connection string containing `User Id=/;TNS_ADMIN=...`
- `dbconnect` can inspect schema, run ad hoc queries, and execute migration-style `.sql` files via `--sql <file>`
