# Notes Guidance (Pass 3)

`notes` exists for exactly one purpose: capture what a reader of the finished CSV could not
figure out just from `src_*`/`dst_*` alone. If the row is a plain, unremarkable 1:1 copy,
leave `notes` blank — a blank `notes` column is a valid, common, and honest final state, not
an unfinished one. Padding every row with a restatement of its own fields ("copies CustomerId
to CustomerId") is noise and makes the genuinely important notes harder to find.

Write from the reader's perspective: they have the row's ten fields in front of them and
nothing else. What would surprise them, or what would they get wrong if they assumed the
obvious?

## Checklist — look for these on every row before deciding notes is blank

- **Transformation** — type conversion, rounding/truncation, unit conversion, case folding,
  string formatting, concatenation of multiple source fields into one destination field (or
  the reverse: one source field split across several destination fields).
- **Renaming** — source and destination names that don't obviously correspond (e.g. source
  `Amt` → destination `TotalAmount`) even though the row's fields already show both names —
  worth a note when the correspondence isn't a simple rename but involves a business rule
  (e.g. "Amt is pre-tax; TotalAmount includes tax computed here").
- **Filtering/business rules** — not every source row reaches the destination (a `WHERE`
  clause, a status check, a feature flag) — say what's excluded.
- **Batching/timing** — synchronous per-request vs. a nightly/scheduled batch job, page size
  for a paginated API call, `GO`-batch or transaction boundaries for a multi-statement SQL
  script.
- **Upsert vs. insert-only vs. append-only** — whether the destination can be overwritten,
  merged, or only ever grows.
- **PII/sensitive data** — flag when a column known to carry PII (name, SSN, DOB, financial
  account number, health data) leaves the system via a non-Database destination (API, File,
  Email) — this is often the single most useful thing a governance-focused datamap surfaces.
  Note whether it's masked, truncated, hashed, or sent as-is.
- **Opaque logic** — a stored procedure whose body isn't visible (see
  `references/detection-patterns.md`), an EF-backed operation that was intentionally not
  mapped, a third-party library doing the actual write internally.
- **Runtime-resolved configuration** — a connection string, base URL, or recipient address
  that comes from Key Vault, App Configuration, or an environment variable rather than a
  literal in source — say what's known (the config key) and what isn't (the actual runtime
  value).
- **Computed values mapped with `src_type: "Runtime"`** — if you mapped a row this way (see
  `references/schema.md` — "Extending the type sets"), the note should name the exact
  expression that produces the value and, if the same value also gets consumed elsewhere
  (e.g. a watermark timestamp that both lands in a table *and* gets POSTed back to an API),
  cross-reference that other flow so a reader doesn't have to re-derive the connection.
- **`*` justification** — any row using the `*` sentinel for a column field must explain why
  here (see `references/schema.md` — "Column granularity"): `SELECT *` used, a dynamically
  built column list, or a deliberate collapse of a wide 1:1 mapping.
- **Retry/idempotency** — an idempotency key, a retry policy, or at-least-once delivery
  semantics that mean the same source row might be written more than once.
- **Authentication/authorization** — worth a brief mention only when it constrains *what*
  data can flow (e.g. "endpoint only returns rows the caller's tenant owns"), not as a
  generic "uses OAuth2" note that doesn't change the reader's understanding of the data.

## Good vs. bad examples

| Bad (restates the fields, or vague) | Good (tells the reader something they couldn't otherwise know) |
|---|---|
| "Copies data from Orders to OrderExtract." | "Amount is rounded to 2 decimals in WarehouseDB; source OrdersDB.TotalAmount is unrounded money." |
| "Uses a stored procedure." | "usp_GetActiveCustomers body not visible from source; dbo.Customers inferred from proc name only, not confirmed by reading the SQL." |
| "Sensitive data." | "SocialSecurityNumber is included in the outbound payload unmasked — no redaction applied before the API call." |
| "All columns." | "SELECT * used; destination schema in WarehouseDB is not statically known to match column-for-column." |
| "Config driven." | "Connection string 'ShippingDb' is an Azure Key Vault reference (@Microsoft.KeyVault(...)); actual database is not visible from source, resolved at app startup." |
| "" (blank, on a row where a business rule actually filters rows) | "Only orders with Status = 'Shipped' are exported; cancelled and pending orders never reach this file." |
| "" (blank, on a genuinely trivial 1:1 field-for-field copy) | *(blank is correct here — nothing to add)* |

## Workflow reminder

Notes are added in Pass 3, one line (or a batch of lines) at a time, via
`scripts/Set-DataMapNotes.ps1` — never by re-writing the whole JSONL file by hand. See the
main `SKILL.md` workflow for the exact invocation and the `-ExpectSrcTbl`/`-ExpectDstTbl`
safety check.
