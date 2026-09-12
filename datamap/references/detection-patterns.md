# Detection Patterns (C#)

Signatures and `rg` (ripgrep) commands for finding each source/destination category in a C#
codebase. Run these from the repo root. Every command targets `*.cs` files; adjust the glob
if the repo also has `.cshtml`/`.razor` files worth scanning (rare for data-flow code).

Read a hit's surrounding method, not just the matched line, before deciding source vs.
destination and before writing a row — the signature tells you *what kind* of flow it is,
the surrounding code tells you *which direction* and *which table/endpoint/file*.

## SQL via ADO.NET

Signatures:
- `SqlConnection`, `OleDbConnection`, `OdbcConnection` (construction, usually near a
  connection-string source — see below)
- `SqlCommand`, `OleDbCommand`, `OdbcCommand`, or the `IDbCommand`/`DbCommand` interfaces
- `.CommandText = "..."` or a `CommandText:` constructor argument
- `.ExecuteReader(...)` → a read (source)
- `.ExecuteNonQuery(...)` → typically a write (`INSERT`/`UPDATE`/`DELETE`/`MERGE`/DDL) — read
  the SQL text to confirm which
- `.ExecuteScalar(...)` → usually a read, but can be a write with `OUTPUT`/`RETURNING`

```bash
rg -tcs 'SqlCommand|OleDbCommand|OdbcCommand|IDbCommand\b|DbCommand\b' -n
rg -tcs 'CommandText\s*=' -n
rg -tcs '\.ExecuteReader\(|\.ExecuteNonQuery\(|\.ExecuteScalar\(' -n
```

Once you have `CommandText`, classify the statement yourself:
- `SELECT ... FROM <t1> [JOIN <t2> ...]` → each of `t1`, `t2`, ... is a **source** table
- `INSERT INTO <t>` / `UPDATE <t>` / `MERGE <t>` (as the target, not the `USING` side) /
  `DELETE FROM <t>` → `<t>` is a **destination** table (the `USING`/joined side of a `MERGE`
  is a **source**)
- A statement can be both directions at once (e.g. `INSERT INTO dst SELECT ... FROM src`) —
  emit one row per source→destination table pair

**Stored procedures**: `CommandType.StoredProcedure` with `CommandText` set to a proc name
means the SQL body is not in this codebase — it's opaque. Record what you *can* see: the
database (from the connection string) and the proc name go in `src_tbl`/`dst_tbl` as
`EXEC <procname>` (pick source or destination by whether the call is read-oriented, e.g. it
populates an output parameter or result set the app then uses, vs. write-oriented, e.g. it's
named `usp_InsertX` / `usp_UpdateX` and the app passes data in). Say in `notes` that the
statement body isn't visible from source and the table-level detail is inferred from the
proc name only, not confirmed.

```bash
rg -tcs 'CommandType\.StoredProcedure' -n -B3
```

## SQL via Dapper

Dapper is a set of extension methods on `IDbConnection`, so the "connection" signatures
above still apply for finding the connection itself. The execution calls:

```bash
rg -tcs '\.Query(Async)?<|\.QueryFirst(OrDefault)?(Async)?<|\.QueryMultiple\(|\.Execute(Async)?\(' -n
```

The SQL text is usually the first string argument (inline, a `const string`, or a resource);
trace it back the same way as ADO.NET `CommandText` above. Dapper's `param` argument (an
anonymous object or DTO) is often the best evidence for which columns participate when the
SQL itself uses `SELECT *` or a stored procedure.

## Entity Framework — explicitly out of scope

`DbContext`, `DbSet<T>`, and LINQ-to-Entities queries are **not** mapped by this skill: EF
translates LINQ to SQL at runtime and the actual executed SQL (or the stored procedure body
behind `FromSqlRaw`/`ExecuteSqlRaw` when those wrap a proc) isn't statically visible from the
C# source with the same confidence as ADO.NET/Dapper's literal command text.

```bash
rg -tcs '\bDbContext\b|\bDbSet<' -n
```

If this codebase uses EF, note it as a gap in your Step 6 report rather than guessing table
names from entity class names — an entity's mapped table can be renamed via `[Table("...")]`
or Fluent API and silently diverge from the class name.

## Connection strings (which database is which)

A codebase touching multiple databases needs each `SqlConnection`/Dapper connection traced
back to a specific database name before you can fill in `src_name`/`dst_name`.

```bash
rg -n '"ConnectionStrings' --glob '*.json'
rg -tcs 'GetConnectionString\(|ConfigurationManager\.ConnectionStrings\[' -n
rg -n '<connectionStrings>' -g '*.config' -A5
rg -tcs 'ConnectionStrings__' -n   # env-var-style override (double underscore = section separator)
```

- `appsettings.json` / `appsettings.<env>.json`: look for a `"ConnectionStrings"` section;
  each named entry usually has `Initial Catalog=<db>` or `Database=<db>` in its value — that's
  your `src_name`/`dst_name`.
- `web.config`/`app.config`: `<connectionStrings><add name="..." connectionString="..." />`.
- `IConfiguration.GetConnectionString("Name")` or `ConfigurationManager.ConnectionStrings["Name"].ConnectionString`
  is how the app pulls the string above into an `SqlConnection` at runtime — match the `"Name"`
  back to the config file entry.
- Environment-variable overrides (`ConnectionStrings__Orders` in ASP.NET Core's env-var
  configuration provider) can replace the config-file value in a given environment — if you
  see this pattern, note in `notes` that the actual database is environment-dependent and
  name the config key rather than asserting one database name as fact.
- **Key Vault / Azure App Configuration**: if the connection string is a Key Vault reference
  (`@Microsoft.KeyVault(...)`) or pulled from App Configuration at startup, the real value
  isn't visible from source at all. Use the config key name as `src_name`/`dst_name` and say
  in `notes` that the actual database is resolved externally at runtime.

## API endpoints

**Outbound calls** (this app calling another system):

```bash
rg -tcs '\bHttpClient\b|IHttpClientFactory|\.GetAsync\(|\.PostAsync\(|\.PutAsync\(|\.PatchAsync\(|\.DeleteAsync\(|\.SendAsync\(' -n
rg -tcs '\bRestClient\b|RestRequest' -n           # RestSharp
rg -tcs '\.WithUrl\(|GetJsonAsync|PostJsonAsync' -n   # Flurl
rg -tcs '\[Get\(|\[Post\(|\[Put\(|\[Delete\(' -n      # Refit interface methods
```

`BaseAddress` (set directly on an `HttpClient`, or via `services.AddHttpClient("name", c => c.BaseAddress = ...)`
in DI startup code) gives you `src_name`/`dst_name`; the path passed to the verb call
(`GetAsync("/v2/customers/5")`) gives you `src_tbl`/`dst_tbl` — prefix it with the verb, e.g.
`GET /v2/customers/{id}` (normalize path parameters to a `{name}` placeholder rather than the
literal value seen in one call site).

A `GET`/response body being read → **source**. A `POST`/`PUT`/`PATCH` request body being sent
→ **destination**. A `DELETE` is usually neither (nothing flows), unless the response body is
consumed.

**Inbound endpoints** (this app receiving data from a caller):

```bash
rg -tcs '\[ApiController\]|\[Route\(|\[HttpGet\]|\[HttpPost\]|\[HttpPut\]|\[HttpDelete\]' -n
rg -tcs '\bapp\.Map(Get|Post|Put|Delete)\(' -n   # minimal API
```

A controller action or minimal-API handler that reads `[FromBody]`/model-bound parameters and
persists or forwards them → the request is a **source** (`src_type: API`, `src_name` = this
app's own base URL/service name, `src_tbl` = the route with its verb). An action that queries
data and returns it in the response → the response is this app acting as a **destination**
for whatever fed the query, viewed from the caller's side (`dst_type: API`) — but more often
it's simpler and more useful to record the *real* upstream source (the DB/file the data came
from) with `dst_type: API` pointing at this app's own exposed route, since that's what a
consumer of the data map actually wants to know: "where did the data behind this endpoint
come from."

## Files

**Reads** (source):

```bash
rg -tcs 'File\.ReadAllText\(|File\.ReadAllLines\(|File\.ReadAllBytes\(|\bStreamReader\b' -n
rg -tcs '\bExcelPackage\b|\.Worksheets\[|\.Cells\[' -n         # EPPlus
rg -tcs '\bXLWorkbook\b' -n                                     # ClosedXML
rg -tcs '\bCsvReader\b' -n                                       # CsvHelper
rg -tcs 'SpreadsheetDocument\.Open\(' -n                         # OpenXML SDK
rg -tcs '\bHSSFWorkbook\b|\bXSSFWorkbook\b' -n                   # NPOI
```

**Writes** (destination):

```bash
rg -tcs 'File\.WriteAllText\(|File\.WriteAllLines\(|File\.WriteAllBytes\(|File\.AppendAllText\(|\bStreamWriter\b' -n
rg -tcs '\.SaveAs\(|package\.Save\(' -n                          # EPPlus / ClosedXML
rg -tcs '\bCsvWriter\b' -n                                       # CsvHelper
rg -tcs 'SpreadsheetDocument\.Create\(' -n                       # OpenXML SDK
```

For either direction, the file path expression gives you `src_tbl`/`dst_tbl` (the leaf
filename — normalize a computed timestamp segment to a token, e.g. `export_{yyyyMMdd}.csv`)
and its directory/share/drive gives you `src_name`/`dst_name`.

## SFTP

```bash
rg -tcs '\bSftpClient\b|\.UploadFile\(|\.DownloadFile\(' -n   # SSH.NET (Renci.SshNet)
rg -tcs '\bSession\b.*WinSCP|WinSCP\.' -n                       # WinSCP .NET assembly
rg -tcs '\bFtpClient\b' -n                                      # FluentFTP (FTP/FTPS — adjust dst_type if plain FTP, not SFTP)
```

`dst_type` is `File (SFTP)`; `dst_name` is the SFTP host (+ remote base directory if constant);
`dst_tbl` is the remote filename. `UploadFile`/`Put`-style calls are destinations;
`DownloadFile`/`Get`-style calls are sources (`src_type: File`, since the schema's source side
doesn't distinguish disk from SFTP the way the destination side does — see `schema.md`).

## SharePoint

```bash
rg -tcs 'Microsoft\.SharePoint\.Client|\bClientContext\b|SaveBinaryDirect\(' -n   # CSOM
rg -tcs 'PnP\.(Framework|Core)|\bPnPContext\b' -n                                  # PnP
rg -tcs 'GraphServiceClient|\.Drives\[|\.Sites\[.*\]\.Drive' -n                    # Microsoft Graph
```

`dst_type` is `File (SharePoint)`; `dst_name` is the site URL or document library; `dst_tbl`
is the uploaded file name (+ folder path within the library if constant).

## Email

```bash
rg -tcs '\bSmtpClient\b|\bMailMessage\b' -n         # System.Net.Mail
rg -tcs '\bMimeMessage\b|MailKit\.' -n               # MailKit/MimeKit
rg -tcs 'SendGridClient|SendGridMessage' -n           # SendGrid SDK
rg -tcs '\.SendMail\(|Users\[.*\]\.SendMail' -n       # Microsoft Graph sendMail
```

`dst_type` is `Email`. `dst_name` is the sending mechanism (SMTP relay host from config, or
the named service — e.g. `"MS Graph sendMail"`); `dst_tbl` is the recipient address, mailing
list, or (if the recipient is computed/config-driven and not a literal in source) the config
key that supplies it. `dst_col` is always `N/A`.
