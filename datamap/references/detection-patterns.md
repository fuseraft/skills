# Detection Patterns (C#)

Regex patterns for finding each source/destination category in a C# codebase, plus the
signatures that motivate them. These are patterns, not tool invocations — run each one with
whichever content-search capability is actually available in the current session:

- **`search_content`** (fuseraft's built-in tool) — the default, reach for it first. Pure
  .NET, no external binary, works identically on Windows/Linux/macOS with zero install:
  `search_content(query: "<pattern>", directory: ".", filePattern: "*.cs")`.
- **`rg`** (ripgrep), only if it's actually on `PATH` in this environment — check once with
  `shell_which rg` (or the equivalent shell-availability check) before relying on it, never
  assume it's installed. It is not bundled with Windows, and often isn't present even in a
  plain Linux shell — a session's own interactive shell can have a convenience wrapper for
  `rg` that a `shell_run` subprocess does not inherit, so "it worked when I typed `rg` once"
  is not proof it's really there. When it is available: `rg -tcs "<pattern>" -n`, and several
  patterns can be OR'd into one call to save round trips — a nice-to-have, never a
  requirement, since every pattern below works identically through `search_content`.

Patterns below are shown as bare regexes (target `*.cs`; adjust the file pattern if the repo
also has `.cshtml`/`.razor` files worth scanning — rare for data-flow code). Read a hit's
surrounding method, not just the matched line, before deciding source vs. destination and
before writing a row — the signature tells you *what kind* of flow it is, the surrounding code
tells you *which direction* and *which table/endpoint/file*.

## File size guidance

Below roughly 300 lines, read the whole file directly instead of relying on a pattern search to
find the relevant lines first — a search can only find a pattern that's actually in the list
below, and a short file is cheap to read in full regardless of whether anything matches.

Above that, pattern search is still the entry point, but expand every hit to the file's
containing **method or class**, not a handful of context lines. Enterprise data-access code is
usually a few well-encapsulated methods even inside a large file, and reading the whole
containing unit is what actually lets you classify source vs. destination correctly — a
`SqlCommand` construction near the top of a 3,000-line file tells you nothing about which
table or direction without the rest of that method.

A large file is also where a missed pattern is most consequential, since there's no "just read
the whole thing" safety net for it. As a second, looser pass over any file large enough to skip
whole-file reading, search its `using` directives for the namespaces this file's signatures
come from (`Microsoft.Data.SqlClient`, `System.Net.Http`, `OfficeOpenXml`, `Dapper`, etc.) — a
hit there with no corresponding signature match downstream in the same file is a sign the
verb-level patterns missed something, worth a closer manual look before moving on.

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

Patterns:
- `SqlCommand|OleDbCommand|OdbcCommand|IDbCommand\b|DbCommand\b`
- `CommandText\s*=`
- `\.ExecuteReader(Async)?\(|\.ExecuteNonQuery(Async)?\(|\.ExecuteScalar(Async)?\(`

Match the `Async`-suffixed overloads too (`ExecuteReaderAsync`, `ExecuteNonQueryAsync`,
`ExecuteScalarAsync`) — they're the more common form in current code, and `\.ExecuteReader\(`
alone does **not** match `.ExecuteReaderAsync(` (no shared trailing `(`).

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

Pattern: `CommandType\.StoredProcedure` — then read a few lines above the hit (the
`SqlCommand` construction that sets it) for the connection and proc name; there's no
substitute for reading the surrounding code here, since the useful context comes *before*
the match, not after.

## SQL via Dapper

Dapper is a set of extension methods on `IDbConnection`, so the "connection" signatures
above still apply for finding the connection itself. The execution calls:

Pattern: `\.Query(Async)?<|\.QueryFirst(OrDefault)?(Async)?<|\.QueryMultiple\(|\.Execute(Async)?\(`

The SQL text is usually the first string argument (inline, a `const string`, or a resource);
trace it back the same way as ADO.NET `CommandText` above. Dapper's `param` argument (an
anonymous object or DTO) is often the best evidence for which columns participate when the
SQL itself uses `SELECT *` or a stored procedure.

## Entity Framework — explicitly out of scope

`DbContext`, `DbSet<T>`, and LINQ-to-Entities queries are **not** mapped by this skill: EF
translates LINQ to SQL at runtime and the actual executed SQL (or the stored procedure body
behind `FromSqlRaw`/`ExecuteSqlRaw` when those wrap a proc) isn't statically visible from the
C# source with the same confidence as ADO.NET/Dapper's literal command text.

Pattern: `\bDbContext\b|\bDbSet<`

If this codebase uses EF, note it as a gap in your Step 6 report rather than guessing table
names from entity class names — an entity's mapped table can be renamed via `[Table("...")]`
or Fluent API and silently diverge from the class name.

## Connection strings (which database is which)

A codebase touching multiple databases needs each `SqlConnection`/Dapper connection traced
back to a specific database name before you can fill in `src_name`/`dst_name`.

Patterns:
- `"ConnectionStrings` — scope the search to `*.json` files (`appsettings.json`,
  `appsettings.<env>.json`); each named entry usually has `Initial Catalog=<db>` or
  `Database=<db>` in its value — that's your `src_name`/`dst_name`.
- `<connectionStrings>` — scope to `*.config` files (`web.config`/`app.config`):
  `<connectionStrings><add name="..." connectionString="..." />`.
- `GetConnectionString\(|ConfigurationManager\.ConnectionStrings\[` — how the app pulls the
  string above into an `SqlConnection` at runtime; match the `"Name"` argument back to the
  config file entry.
- `ConnectionStrings__` — an env-var-style override (double underscore = section separator
  in ASP.NET Core's configuration provider).

Notes:
- Environment-variable overrides (`ConnectionStrings__Orders`) can replace the config-file
  value in a given environment — if you see this pattern, note in `notes` that the actual
  database is environment-dependent and name the config key rather than asserting one
  database name as fact.
- **Key Vault / Azure App Configuration**: if the connection string is a Key Vault reference
  (`@Microsoft.KeyVault(...)`) or pulled from App Configuration at startup, the real value
  isn't visible from source at all. Use the config key name as `src_name`/`dst_name` and say
  in `notes` that the actual database is resolved externally at runtime.

## API endpoints

**Outbound calls** (this app calling another system):

Patterns:
- `\bHttpClient\b|IHttpClientFactory|\.GetAsync\(|\.PostAsync\(|\.PutAsync\(|\.PatchAsync\(|\.DeleteAsync\(|\.SendAsync\(`
- `\.(Get|Post|Put|Patch|Delete)FromJsonAsync\b|\.(Post|Put|Patch)AsJsonAsync\b` — `System.Net.Http.Json` extensions
- `\bRestClient\b|RestRequest` — RestSharp
- `\.WithUrl\(|GetJsonAsync|PostJsonAsync` — Flurl
- `\[Get\(|\[Post\(|\[Put\(|\[Delete\(` — Refit interface methods

The `System.Net.Http.Json` extension methods (`GetFromJsonAsync`, `PostAsJsonAsync`, etc.)
are at least as common as the bare verb calls in current code and are **not** matched by the
first pattern above (`.PostAsJsonAsync(` doesn't contain `.PostAsync(` as a substring) - always
run the second pattern too, and don't rely on the bare-verb pattern alone to rule out a JSON API
call. The `\bHttpClient\b` hit on the class itself still anchors you to the right file either
way, which is why "read the surrounding method" (not just the matched line) matters here.

`BaseAddress` (set directly on an `HttpClient`, or via `services.AddHttpClient("name", c => c.BaseAddress = ...)`
in DI startup code) gives you `src_name`/`dst_name`; the path passed to the verb call
(`GetAsync("/v2/customers/5")`) gives you `src_tbl`/`dst_tbl` — prefix it with the verb, e.g.
`GET /v2/customers/{id}` (normalize path parameters to a `{name}` placeholder rather than the
literal value seen in one call site).

A `GET`/response body being read → **source**. A `POST`/`PUT`/`PATCH` request body being sent
→ **destination**. A `DELETE` is usually neither (nothing flows), unless the response body is
consumed.

**Inbound endpoints** (this app receiving data from a caller):

Patterns:
- `\[ApiController\]|\[Route\(|\[HttpGet\]|\[HttpPost\]|\[HttpPut\]|\[HttpDelete\]`
- `\bapp\.Map(Get|Post|Put|Delete)\(` — minimal API

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

Patterns:
- `File\.ReadAllText\(|File\.ReadAllLines\(|File\.ReadAllBytes\(|\bStreamReader\b`
- `\bExcelPackage\b|\.Worksheets\[|\.Cells\[` — EPPlus
- `\bXLWorkbook\b` — ClosedXML
- `\bCsvReader\b` — CsvHelper
- `SpreadsheetDocument\.Open\(` — OpenXML SDK
- `\bHSSFWorkbook\b|\bXSSFWorkbook\b` — NPOI

**Writes** (destination):

Patterns:
- `File\.WriteAllText\(|File\.WriteAllLines\(|File\.WriteAllBytes\(|File\.AppendAllText\(|\bStreamWriter\b`
- `\.SaveAs\(|package\.Save\(` — EPPlus / ClosedXML
- `\bCsvWriter\b` — CsvHelper
- `SpreadsheetDocument\.Create\(` — OpenXML SDK

For either direction, the file path expression gives you `src_tbl`/`dst_tbl` (the leaf
filename — normalize a computed timestamp segment to a token, e.g. `export_{yyyyMMdd}.csv`)
and its directory/share/drive gives you `src_name`/`dst_name`.

## SFTP

Patterns:
- `\bSftpClient\b|\.UploadFile\(|\.DownloadFile\(` — SSH.NET (Renci.SshNet)
- `\bSession\b.*WinSCP|WinSCP\.` — WinSCP .NET assembly
- `\bFtpClient\b` — FluentFTP (FTP/FTPS — adjust `dst_type` if plain FTP, not SFTP)

`dst_type` is `File (SFTP)`; `dst_name` is the SFTP host (+ remote base directory if constant);
`dst_tbl` is the remote filename. `UploadFile`/`Put`-style calls are destinations;
`DownloadFile`/`Get`-style calls are sources (`src_type: File`, since the schema's source side
doesn't distinguish disk from SFTP the way the destination side does — see `schema.md`).

## SharePoint

Patterns:
- `Microsoft\.SharePoint\.Client|\bClientContext\b|SaveBinaryDirect\(` — CSOM
- `PnP\.(Framework|Core)|\bPnPContext\b` — PnP
- `GraphServiceClient|\.Drives\[|\.Sites\[.*\]\.Drive` — Microsoft Graph

`dst_type` is `File (SharePoint)`; `dst_name` is the site URL or document library; `dst_tbl`
is the uploaded file name (+ folder path within the library if constant).

## Email

Patterns:
- `\bSmtpClient\b|\bMailMessage\b` — System.Net.Mail
- `\bMimeMessage\b|MailKit\.` — MailKit/MimeKit
- `SendGridClient|SendGridMessage` — SendGrid SDK
- `\.SendMail\(|Users\[.*\]\.SendMail` — Microsoft Graph sendMail

`dst_type` is `Email`. `dst_name` is the sending mechanism (SMTP relay host from config, or
the named service — e.g. `"MS Graph sendMail"`); `dst_tbl` is the recipient address, mailing
list, or (if the recipient is computed/config-driven and not a literal in source) the config
key that supplies it. `dst_col` is always `N/A`.
