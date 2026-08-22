# dbconnect examples

## List saved connections
`scripts\dbconnect-list.bat`

## SQL Server connectivity check
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --conn "<sqlserver-connection-string>" --sql "SELECT 1"`

## Oracle connectivity check
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --oracle --conn "<oracle-connection-string>" --sql "SELECT 1 FROM dual"`

## Use a named connection
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --use SqlServer_Prod --sql "SELECT TOP 1 * FROM dbo.MyTable"`

## Inspect schema
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --use SqlServer_Prod --sql "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS MAX_LENGTH, IS_NULLABLE, COLUMN_DEFAULT FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'MyTable' ORDER BY ORDINAL_POSITION" --output output.csv`

## Run a migration or other SQL file (requires --allow-write, may contain GO batches)
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --use SqlServer_Prod --sql .\migrations\001_init.sql --allow-write`

## Run with BAT wrapper
`scripts\dbconnect-run.bat --use SqlServer_Prod --sql "SELECT TOP 10 * FROM dbo.MyTable" --output output.csv`

## Large result set, cap console preview
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --use SqlServer_Prod --sql "SELECT * FROM dbo.BigTable" --max-rows 50`

## Large result set, export everything (no truncation)
`powershell -ExecutionPolicy Bypass -File scripts\dbconnect-run.ps1 --use SqlServer_Prod --sql "SELECT * FROM dbo.BigTable" --output big-table.csv`
