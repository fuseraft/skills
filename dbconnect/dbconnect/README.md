# dbconnect

A simple CLI for connecting to Oracle and SQL Server databases and executing SQL in agentic workflows.

## Getting Started

Build the application with:

```ps1
PS> .\build.ps1
```

## CLI Flags

| Flag | Description |
| ---- | ----------- |
| `--help` | Print the help text. |
| `--oracle` | Connect to an Oracle database using Kerberos. |
| `--conn` | The connection string to use. |
| `--use` | Specify a named connection to use. |
| `--list` | List available connections. |
| `--sql "sql statements;"` | SQL text to execute. |
| `--sql <file_name>` | Execute SQL from a file. SQL Server input is split on lines containing only `GO` and run as separate batches. |
| `--output <file_name>` | Write results to a CSV file. CSV exports are never truncated by `--max-rows`. |
| `--max-rows <n>` | Cap console table output at `n` rows (default 200). Does not affect `--output` CSV exports. |
| `--allow-write` | Permit INSERT/UPDATE/DELETE/MERGE/DDL statements. Without it, dbconnect blocks write statements before opening a connection. |

## Connections

You can create a `<NAMED>.connections` file for `dbconnect` to reference when connecting to a database.

These are simple JSON files that store connection information:

Example `DB.connections`:

```json
{
    "connections": [
        {
            "name": "Oracle_Test",
            "connectionstring": "Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oradb.fuseraft.com)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=fuseraft.oraclevcn.com)));User Id=/;TNS_ADMIN=C:\\TNS_ADMIN",
            "type": "oracle"
        },
        {
            "name": "SqlServer_Prod",
            "connectionstring": "Data Source=fuseraft\\fuseraftdb;Initial Catalog=FuseraftDb;Trusted_Connection=yes;TrustServerCertificate=true;",
            "type": "mssql"
        }
    ]
}
```