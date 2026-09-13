# Detection Patterns (C#)

Regex patterns for finding each source/destination category, plus what each one tells you.
These are patterns, not tool invocations — run them with whichever content-search capability
is actually available:

- **`search_content`** (fuseraft's built-in tool) — the default. Pure .NET, no install, works
  identically on every OS: `search_content(query: "<pattern>", directory: ".", filePattern: "*.cs")`.
- **`rg`**, only if a shell-availability check (e.g. `shell_which rg`) actually confirms it's on
  `PATH` — never assume it. It isn't bundled with Windows, and often isn't present in a plain
  Linux shell either; an interactive shell's own convenience wrapper for `rg` is not proof a
  `shell_run` subprocess has a real one. `rg -tcs "<pattern>" -n` when it is available.

Target `*.cs` (adjust if the repo also has `.cshtml`/`.razor` worth scanning — rare for
data-flow code). Read a hit's surrounding method, not just the matched line — the pattern tells
you *what kind* of flow it is, the surrounding code tells you *which direction* and *which
table/endpoint/file*.

## File size guidance

Below ~300 lines, read the whole file directly rather than searching it first — a search only
finds patterns that are in the list below, and a short file is cheap to read in full regardless.

Above that, search is still the entry point, but expand every hit to the containing **method
or class**, not a few context lines — a `SqlCommand` construction near the top of a 3,000-line
file tells you nothing about table or direction without the rest of that method.

A missed pattern matters most on a large file, since there's no whole-file-read safety net. As
a second, looser pass on files too large to read whole, search their `using` directives for the
namespaces below (`Microsoft.Data.SqlClient`, `System.Net.Http`, `OfficeOpenXml`, etc.) — a hit
there with no corresponding pattern match downstream is a sign something was missed.

## SQL via ADO.NET

Patterns:
- `SqlCommand|OleDbCommand|OdbcCommand|IDbCommand\b|DbCommand\b` — construction, usually near a connection-string source (see below)
- `CommandText\s*=` — the SQL text
- `\.ExecuteReader(Async)?\(` → read (source); `\.ExecuteNonQuery(Async)?\(` → typically write (read the SQL to confirm); `\.ExecuteScalar(Async)?\(` → usually read. Match the `Async` overloads too — they're the more common form, and `\.ExecuteReader\(` alone does **not** match `.ExecuteReaderAsync(`.

Once you have `CommandText`, classify the statement yourself:
- `SELECT ... FROM <t1> [JOIN <t2> ...]` → each of `t1`, `t2`, ... is a **source** table
- `INSERT INTO <t>` / `UPDATE <t>` / `MERGE <t>` (target side) / `DELETE FROM <t>` → **destination** (the `USING`/joined side of a `MERGE` is a **source**)
- A statement can be both directions (`INSERT INTO dst SELECT ... FROM src`) — one row per source→destination table pair

**Stored procedures**: `CommandType.StoredProcedure` (pattern: `CommandType\.StoredProcedure`,
then read a few lines *above* the hit for the `SqlCommand` construction — the useful context
comes before the match, not after) means the SQL body isn't in this codebase. Record what's
visible: database (from the connection string) and proc name as `src_tbl`/`dst_tbl` =
`EXEC <procname>` (source if read-oriented, destination if it's named `usp_InsertX`/`usp_UpdateX`
and the app passes data in). Say in `notes` that the body isn't visible and the table-level
detail is inferred from the proc name only.

## SQL via Dapper

Dapper is extension methods on `IDbConnection`, so the ADO.NET connection patterns above still
find the connection. Execution calls:

Pattern: `\.Query(Async)?<|\.QueryFirst(OrDefault)?(Async)?<|\.QueryMultiple\(|\.Execute(Async)?\(`

The SQL text is usually the first string argument; trace it back like ADO.NET `CommandText`.
Dapper's `param` argument (anonymous object or DTO) is often the best evidence for which
columns participate when the SQL itself uses `SELECT *` or a stored procedure.

## Entity Framework — explicitly out of scope

`DbContext`/`DbSet<T>`/LINQ-to-Entities are **not** mapped: EF translates LINQ to SQL at
runtime, and the executed SQL (or the proc body behind `FromSqlRaw`/`ExecuteSqlRaw`) isn't
statically visible with ADO.NET/Dapper's confidence. Pattern: `\bDbContext\b|\bDbSet<`. If
found, note it as a gap rather than guessing table names from entity class names — those can
be renamed via `[Table("...")]` or Fluent API and silently diverge.

## Connection strings (which database is which)

Patterns:
- `"ConnectionStrings` (scope to `*.json`) — `appsettings.json`/`appsettings.<env>.json`; each named entry usually has `Initial Catalog=<db>` or `Database=<db>` — that's your `src_name`/`dst_name`.
- `<connectionStrings>` (scope to `*.config`) — `web.config`/`app.config`.
- `GetConnectionString\(|ConfigurationManager\.ConnectionStrings\[` — how the app pulls the string above at runtime; match the `"Name"` back to the config entry.
- `ConnectionStrings__` — env-var-style override (double underscore = section separator).

If an environment-variable override is present, note in `notes` that the actual database is
environment-dependent and name the config key rather than asserting one database as fact. If
the value is a Key Vault reference (`@Microsoft.KeyVault(...)`) or from App Configuration, it
isn't visible from source at all — use the config key as `src_name`/`dst_name` and say so.

## API endpoints

**Outbound** (this app calling another system). Patterns:
- `\bHttpClient\b|IHttpClientFactory|\.GetAsync\(|\.PostAsync\(|\.PutAsync\(|\.PatchAsync\(|\.DeleteAsync\(|\.SendAsync\(`
- `\.(Get|Post|Put|Patch|Delete)FromJsonAsync\b|\.(Post|Put|Patch)AsJsonAsync\b` — `System.Net.Http.Json` extensions. At least as common as the bare verb calls and **not** matched by the pattern above (`.PostAsJsonAsync(` doesn't contain `.PostAsync(`) — always check both; the `\bHttpClient\b` hit still anchors you to the file either way.
- `\bRestClient\b|RestRequest` — RestSharp
- `\.WithUrl\(|GetJsonAsync|PostJsonAsync` — Flurl
- `\[Get\(|\[Post\(|\[Put\(|\[Delete\(` — Refit

`BaseAddress` (on the `HttpClient`, or via `services.AddHttpClient("name", c => c.BaseAddress = ...)`)
gives you `src_name`/`dst_name`; the verb call's path gives `src_tbl`/`dst_tbl`, prefixed with
the verb (`GET /v2/customers/{id}`, path params normalized to `{name}`). `GET` → **source**;
`POST`/`PUT`/`PATCH` body → **destination**; `DELETE` is usually neither unless the response
is consumed.

**Inbound** (this app receiving data from a caller). Patterns:
- `\[ApiController\]|\[Route\(|\[HttpGet\]|\[HttpPost\]|\[HttpPut\]|\[HttpDelete\]`
- `\bapp\.Map(Get|Post|Put|Delete)\(` — minimal API

An action reading `[FromBody]`/model-bound parameters and persisting/forwarding them is a
**source** (`src_type: API`, `src_name` = this app's own base URL, `src_tbl` = the route+verb).
For an action that queries and returns data, it's usually more useful to record the *real*
upstream source (the DB/file) with `dst_type: API` pointing at this app's own route, since
that's what a data-map consumer actually wants: where the data behind the endpoint came from.

## Files

**Reads**: `File\.ReadAllText\(|File\.ReadAllLines\(|File\.ReadAllBytes\(|\bStreamReader\b`;
`\bExcelPackage\b|\.Worksheets\[|\.Cells\[` (EPPlus); `\bXLWorkbook\b` (ClosedXML); `\bCsvReader\b`
(CsvHelper); `SpreadsheetDocument\.Open\(` (OpenXML SDK); `\bHSSFWorkbook\b|\bXSSFWorkbook\b` (NPOI).

**Writes**: `File\.WriteAllText\(|File\.WriteAllLines\(|File\.WriteAllBytes\(|File\.AppendAllText\(|\bStreamWriter\b`;
`\.SaveAs\(|package\.Save\(` (EPPlus/ClosedXML); `\bCsvWriter\b` (CsvHelper);
`SpreadsheetDocument\.Create\(` (OpenXML SDK).

None of these patterns cover every Excel/Office library — e.g. `Microsoft.Office.Interop.Excel`
(COM automation) has no signature here at all. The file-size guidance above is the real
safety net for a gap like this: a small file gets read whole regardless of what matches.

Either direction: the file path's leaf gives `src_tbl`/`dst_tbl` (normalize a computed
timestamp segment to a token, e.g. `export_{yyyyMMdd}.csv`); its directory/share/drive gives
`src_name`/`dst_name`.

## SFTP

Patterns: `\bSftpClient\b|\.UploadFile\(|\.DownloadFile\(` (SSH.NET); `\bSession\b.*WinSCP|WinSCP\.`
(WinSCP); `\bFtpClient\b` (FluentFTP — adjust `dst_type` if it's plain FTP, not SFTP; the schema
has no built-in `dst_type` for plain FTP either — extend it, e.g. `File (FTP)`, and note that
it's intentional). `dst_type: File (SFTP)`; `dst_name` = host (+ remote base dir if constant);
`dst_tbl` = remote filename. Upload/`Put` = destination; Download/`Get` = source (`src_type: File`
— the schema's source side doesn't distinguish disk from SFTP; see `schema.md`).

## SharePoint

Patterns: `Microsoft\.SharePoint\.Client|\bClientContext\b|SaveBinaryDirect\(` (CSOM);
`PnP\.(Framework|Core)|\bPnPContext\b` (PnP); `GraphServiceClient|\.Drives\[|\.Sites\[.*\]\.Drive`
(Microsoft Graph). `dst_type: File (SharePoint)`; `dst_name` = site URL or library; `dst_tbl` =
uploaded file name (+ folder path if constant).

## Email

Patterns: `\bSmtpClient\b|\bMailMessage\b` (System.Net.Mail); `\bMimeMessage\b|MailKit\.`
(MailKit/MimeKit); `SendGridClient|SendGridMessage` (SendGrid); `\.SendMail\(|Users\[.*\]\.SendMail`
(MS Graph). `dst_type: Email`; `dst_name` = sending mechanism (SMTP host, or named service);
`dst_tbl` = recipient/list, or the config key if it's computed rather than a literal. `dst_col`
is always `N/A`.
