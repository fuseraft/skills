# Datamap Schema

Every line of a datamap JSONL file is one JSON object with exactly these ten keys, in
this order. The order isn't meaningful to a JSON parser, but every script in this skill
writes and re-serializes fields in this order so the file stays diff-friendly.

| # | Field | Meaning |
|---|-------|---------|
| 1 | `name` | Application/repo name. Constant across every row produced in one pass of this skill. |
| 2 | `src_type` | `Database`, `API`, or `File` (extensible — see "Extending the type sets" below). |
| 3 | `src_name` | Source location — see the per-type table below. |
| 4 | `src_tbl` | Source object — see the per-type table below. |
| 5 | `src_col` | Source column name, or `N/A` — see "Column granularity" below. |
| 6 | `dst_type` | `Database`, `API`, `File (Disk)`, `File (SFTP)`, `File (SharePoint)`, or `Email` (extensible). |
| 7 | `dst_name` | Destination location — see the per-type table below. |
| 8 | `dst_tbl` | Destination object — see the per-type table below. |
| 9 | `dst_col` | Destination column name, or `N/A` — see "Column granularity" below. |
| 10 | `notes` | Blank in Pass 1. Populated in Pass 3 with transformation rules or other non-obvious, important detail. Blank is a valid final value when there's genuinely nothing to add. |

Every field except `notes` must always hold a non-blank string. There is no field where
"leave it empty" is correct — use one of the two sentinel values instead:

- **`N/A`** — this side of the flow has no column concept at all (API or File on either
  side; Email; anything non-Database). Always literally the three characters `N/A`, not
  `n/a`, `None`, or an empty string — `Test-DataMapJsonl.ps1` treats an empty string in a
  required field as a hard error precisely so it can't hide behind "well it's basically N/A".
- **`*`** — this side is a Database column, but the specific column(s) aren't statically
  resolvable (e.g. `SELECT *`, a dynamically built column list, `INSERT` targeting an
  unknown/generated schema). Always pair `*` with a `notes` entry in Pass 3 explaining why
  (see `references/notes-guidance.md`).

## Per-type field conventions

`src_name`/`dst_name` is the **location** a flow's endpoint lives at; `src_tbl`/`dst_tbl` is
the **specific object** accessed within that location. The pairing is what changes per type:

| Type | `*_name` (location) | `*_tbl` (object) |
|---|---|---|
| Database | Database name (`Initial Catalog` / `Database=` from the connection string) | Schema-qualified table name, e.g. `dbo.Orders` |
| API | Base URL (scheme + host, e.g. `https://api.example.com`) — for an endpoint this app exposes, its own base URL or service name | Endpoint route, prefixed with the HTTP verb, e.g. `GET /v2/customers/{id}` or `POST /v1/shipments` |
| File | Location: folder path, file share (`\\host\share`), or SFTP/SharePoint host+base path | The file name itself, e.g. `customers.xlsx` — include a date/timestamp token literally if the code builds one (e.g. `export_{yyyyMMdd}.csv`) |
| Email (`dst_type` only) | The sending mechanism: SMTP relay host/name, or the service used (e.g. `MailKit via smtp.example.com`, `MS Graph sendMail`) | Recipient(s) or distribution list, e.g. `ops-team@example.com`; if the recipient is dynamic/config-driven, name the config key instead of guessing an address |

Notes:
- `src_name`/`src_tbl` for **File** are not meant to hold the identical string twice — split
  location from filename even when the source only exposes one path string; derive the split
  yourself (directory vs leaf name).
- Email never appears as `src_type` in this schema (nothing in a C# app "sources" data by
  receiving email in a mapped sense) — it's `dst_type` only.
- `API` as `src_type` covers both directions your app can pull data through an API:
  - **Outbound**: this app calls a third-party API and consumes the response. `src_name` is
    the third party's base URL.
  - **Inbound**: this app exposes an endpoint (a controller action, a minimal API route) and
    a caller's request body is the data source. `src_name` is this app's own base URL or
    service name.

  See `references/detection-patterns.md` for how to tell which direction a given piece of
  code represents.

## Column granularity

Column-level detail (`src_col`/`dst_col` holding a real name rather than `N/A`) only ever
applies on the **Database side** of a flow. This follows directly from the schema: API and
File never have a column concept, on either side, regardless of whether they're the source
or the destination of that particular row.

That leaves four shapes:

| Flow | `src_col` | `dst_col` |
|---|---|---|
| Database → Database | real column name, or `*` | real column name, or `*` |
| Database → API/File/Email | real column name, or `*` (worth enumerating — this is often the most governance-relevant row, e.g. tracing which columns leave the system) | `N/A` always |
| API/File → Database | `N/A` always | real column name, or `*` (this is usually the most valuable direction to get right — it's the map of which inbound fields land in which columns) |
| API/File → API/File/Email | `N/A` always | `N/A` always |

### When to split by column vs. collapse with `*`

Splitting one row per column gives the most precise map but can explode row count for wide
tables. Use judgment:

- **Split by column** when the mapping is non-trivial per column — renamed fields, different
  transformations per column, only some columns of a wide table actually participate, or the
  column-level detail is exactly what the user asked this data map to surface (e.g. a PII
  audit needs to know *which* columns move, not just that "some columns" do).
- **Collapse to one row with `*`** when it's a straightforward 1:1 projection across most or
  all columns of a table (e.g. `SELECT *` into a matching schema, or a bulk upsert with an
  explicit but very long column list that maps name-for-name with no transformation). Say so
  in `notes` — e.g. `"all columns copied 1:1 by name; no renaming or transformation"`.

Don't emit one row per column *and* a separate collapsed `*` row for the same flow — pick one
representation for a given source/destination object pair.

## Extending the type sets

`src_type` (`Database`, `API`, `File`) and `dst_type` (`Database`, `API`, `File (Disk)`,
`File (SFTP)`, `File (SharePoint)`, `Email`) are the recommended sets, not a closed enum —
the user's original spec calls them out as examples ("Database, API, etc."). A value outside
these sets is a **warning**, not a validation error, from `Test-DataMapJsonl.ps1`.

Reasonable reasons to go outside the set: a message queue (`src_type: "Queue"`), a
config/environment-variable source, a cache (Redis) as either side, or **`"Runtime"`** for a
value the application computes itself rather than reads from anywhere external — a
`DateTime.UtcNow`/`Guid.NewGuid()` timestamp or correlation ID, a hardcoded constant, a
counter. If you do, keep the value consistent across the whole datamap (don't mix `"Queue"`
and `"MessageQueue"` for the same concept in one file) and consider naming the addition in
your final report to the user so they can decide whether to fold it into a future schema
revision.

**`Runtime` as `src_type`** is the answer to a specific recurring judgment call: a destination
column or API payload field is populated from something computed in-process (a watermark
timestamp being saved, an audit/load-time column, a generated ID) rather than read from a
source table, file, or API response. Two resolutions are both defensible:
- **Map it** with `src_type: "Runtime"`, `src_name` naming the process/component that computes
  it (e.g. `"SalesSyncJob process"`), `src_tbl` naming the expression (e.g.
  `"DateTime.UtcNow (runStartedUtc)"`), `src_col: "N/A"` — this surfaces the row in the CSV
  for governance/completeness, at the cost of one `Test-DataMapJsonl.ps1` warning per row
  (`src_type` outside the recommended set).
- **Don't map it**, and call it out in your Step 6 report instead ("`SalesFact.LoadedUtc` is a
  computed timestamp, not sourced from any table — not mapped as a row").

Prefer mapping it with `Runtime` when the value's *destination* is itself governance-relevant
(it lands in a table/file/API a compliance reviewer cares about) - the CSV is then a complete
inventory of everything that reaches that destination, computed or not. Prefer leaving it
unmapped when the computed value is purely internal bookkeeping with no interesting
destination of its own. Either way, be consistent within one datamap run.

## Worked shape (all four flow directions)

```json
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"CustomerId","dst_type":"API","dst_name":"https://api.shipping.example.com","dst_tbl":"POST /v1/shipments","dst_col":"N/A","notes":""}
{"name":"OrderService","src_type":"File","src_name":"\\\\fileshare\\imports","src_tbl":"customers.xlsx","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.Customers","dst_col":"*","notes":""}
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"*","dst_type":"Email","dst_name":"Corporate SMTP Relay","dst_tbl":"ops-team@example.com","dst_col":"N/A","notes":""}
{"name":"OrderService","src_type":"API","src_name":"https://api.partner.example.com","src_tbl":"GET /v2/inventory/{sku}","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.InventorySnapshot","dst_col":"QuantityOnHand","notes":""}
```

See `references/examples.md` for these same flows with `notes` populated (Pass 3) and the
resulting CSV.
