---
name: datamap
description: "Map data flow through a C# codebase from every source (executed SQL via ADO.NET/Dapper, outbound/inbound API calls, files read via EPPlus/ClosedXML/CsvHelper/etc.) to every destination (database tables, API endpoints, files on disk/SFTP/SharePoint, email), producing a validated JSONL data map and a deterministic CSV export. Trigger when the user asks to document data lineage, build a data map, trace where data comes from and goes to, or produce a source-to-destination inventory for a .NET application or repo. Entity Framework is explicitly out of scope as a SQL source (its generated SQL/proc text isn't statically visible) - flag EF usage as a gap rather than guessing at its SQL."
---

# Data Map

Produce a source-to-destination data map for a C# application: every place data is
read from, every place it ends up, and (once the structure is right) the non-obvious
details a future reader would need — transformations, truncation, masking, opaque
stored procedures, runtime-resolved connection strings.

Output is JSONL first (one JSON object per data-flow row), validated deterministically,
then converted to CSV. The four passes are always run in order and never merged —
each one has a single job and a hard validation gate before the next begins.

## When to Use

Use this skill when the user wants to:
- Document data lineage / data flow for a C# application or repo
- Build an inventory of every database read/write, API call, file I/O, and email send
- Answer "where does this data come from" or "where does this column end up" across a codebase
- Produce a governance/compliance artifact (e.g. tracing PII movement) from static analysis of source code

Do **not** use this skill for:
- Runtime/dynamic tracing (APM, query logs, network capture) — this is static source analysis only
- Entity Framework Core/6 LINQ queries — EF's generated SQL and stored-procedure bodies are not visible from the C# source; note EF usage as an out-of-scope gap in a row's `notes` (or a summary note) rather than guessing at table/column names
- Languages other than C# — the detection patterns in `references/detection-patterns.md` are C#-specific

## Inputs to Gather

Before starting Pass 1, confirm:
1. **Repo/app name** — becomes the `name` field on every row. If mapping multiple repos in one session, run the passes once per repo (don't interleave).
2. **Scope** — whole repo, or specific projects/directories within it?
3. **Output paths** — where should `<name>.jsonl` and `<name>.csv` be written? Default to the repo root if not specified.
4. **Known connection strings / config files already in hand** — if the user already knows which `appsettings*.json` or connection-string names matter, use them directly instead of rediscovering them.

## Workflow

### Step 0: Discover flows

Read `references/detection-patterns.md` before scanning — it has the exact signatures, search
patterns, and tool guidance (don't assume `rg` is installed; fuseraft's own `search_content` is
the reliable default) for:
- SQL via ADO.NET/Dapper, plus connection-string resolution
- Outbound API calls and inbound endpoints this app exposes
- File reads/writes, SFTP, SharePoint, email

For each hit, read enough surrounding code to tell source from destination — the same table or
endpoint can be both, in different flows; each direction is its own row.

Read `references/schema.md` before writing any rows — getting the field conventions wrong
means redoing Pass 1.

### Step 1: Generate the JSONL (Pass 1 — structural)

For each flow found, append one row with `notes` left blank. Prefer the scripts over
hand-writing JSON lines — they enforce the schema and reject bad input before it reaches
the file:

```bash
pwsh -File scripts/New-DataMapEntry.ps1 -Path <name>.jsonl \
  -Name "<repo/app name>" -SrcType Database -SrcName "OrdersDB" -SrcTbl "dbo.Orders" -SrcCol "CustomerId" \
  -DstType API -DstName "https://api.shipping.example.com" -DstTbl "POST /v1/shipments" -DstCol "N/A"
```

For a batch of rows discovered in one pass over a file (typical — a single controller or
repository class usually yields several flows at once), write them to a local JSON array
file and append them all in one validated, all-or-nothing call:

```bash
pwsh -File scripts/New-DataMapEntry.ps1 -Path <name>.jsonl -FromJson ./new-rows.json
```

If a row fails validation (missing field, blank value where a sentinel was needed), the
script rejects it and writes nothing — fix the row and retry rather than patching the file
by hand.

### Step 2: Validate structurally (Pass 2 gate)

```bash
pwsh -File scripts/Test-DataMapJsonl.ps1 -Path <name>.jsonl
```

This must report `"valid": true` (exit code 0) before moving on. It confirms every line is a
JSON object carrying exactly the ten datamap fields with no blank values (aside from `notes`,
which is allowed to be empty at this stage). Warnings (e.g. an unrecognized `src_type`) don't
block progress — review them, but they're advisory.

### Step 3: Annotate notes (Pass 3 — semantic)

Iterate the JSONL in order (by 1-based line number) and decide, for each row, whether there's
something non-obvious worth recording — see `references/notes-guidance.md` for the checklist
and good/bad examples. Leave `notes` blank when there's genuinely nothing to add; don't pad it.

Update one row:

```bash
pwsh -File scripts/Set-DataMapNotes.ps1 -Path <name>.jsonl -LineNumber 3 \
  -Notes "Amount is rounded to 2 decimals in WarehouseDB; source is unrounded money in OrdersDB." \
  -ExpectDstTbl "dbo.OrderExtract"
```

The `-ExpectSrcTbl`/`-ExpectDstTbl` checks are optional but recommended — they confirm you're
editing the row you think you are before it gets overwritten, which matters when iterating many
lines in sequence. A mismatch rejects the edit with no change made.

For a batch of notes decided in one analysis pass, write `{ "line": N, "notes": "...", "expectSrcTbl": "...", "expectDstTbl": "..." }`
entries to a local JSON array file and apply them atomically:

```bash
pwsh -File scripts/Set-DataMapNotes.ps1 -Path <name>.jsonl -Updates ./notes-batch.json
```

Every line, every other field, is untouched by this script except the ones you target — it
never reformats or reorders the file.

### Step 4: Validate the final JSONL (Pass 4 gate)

Re-run the same validator:

```bash
pwsh -File scripts/Test-DataMapJsonl.ps1 -Path <name>.jsonl
```

Must pass before conversion. If you skipped rows in Step 3 intentionally (blank notes is
valid), that's fine — this pass only re-checks structure, same as Step 2.

### Step 5: Convert to CSV (final pass)

```bash
pwsh -File scripts/ConvertTo-DataMapCsv.ps1 -JsonlPath <name>.jsonl -CsvPath <name>.csv
```

This re-validates before writing (refuses to produce a CSV from an invalid JSONL) and then
writes a deterministic RFC 4180 CSV: fixed column order, CRLF line endings, UTF-8 with BOM
(so Excel opens non-ASCII notes correctly). Row order matches the JSONL unless `-Sort` is
passed, which orders rows canonically by every field left to right — useful when you want
byte-identical output regardless of the order flows happened to be discovered in.

### Step 6: Report

Tell the user the row count, the output paths, and call out anything from Step 0 that was
explicitly out of scope (EF-backed data access found but not mapped, opaque stored procedures
where only the proc name — not its body — is known, connection strings resolved from Key Vault
or App Configuration at runtime rather than statically visible).

## Rules

- Follow the four passes in order. Never write `notes` during Pass 1, and never add or
  remove structural rows during Pass 3 — that's a Pass 1 job. If Pass 3 analysis reveals a
  missed flow, go back and add it with `New-DataMapEntry.ps1`, then re-validate before
  resuming notes.
- Every field except `notes` must always hold a value — use the sentinel `N/A` (no column
  concept — see `references/schema.md`) or `*` (all columns / not statically resolvable)
  instead of leaving anything blank.
- `src_col`/`dst_col` only ever carry real column names on the Database side of a flow. The
  other side (API, File, Email) is always `N/A` on that side's column field, regardless of
  which side that is — see `references/schema.md` for the full per-type field table.
- Don't guess at SQL text hidden inside a stored procedure or an EF-generated query. Record
  what's known (the proc name, the DbSet/table if visible) and say what's opaque in `notes`.
- Don't invent connection strings, base URLs, or file paths. If a value is resolved from
  Key Vault, App Configuration, or an environment variable at runtime, put the literal
  reference you can see in source (e.g. the config key name) in `src_name`/`dst_name` and
  explain the runtime resolution in `notes`.
- Prefer the bundled scripts over hand-editing the JSONL — they're the deterministic
  guarantee that every line has all ten keys and no silently-blank required field. Using
  `shell_run`/raw `Bash` to invoke them is expected; it's hand-authoring the JSON text
  without going through validation that this skill exists to avoid.

## References

- `references/schema.md` — the ten fields in detail, per-source-type field conventions (what
  `src_name` vs `src_tbl` means for Database/API/File/Email on each side), sentinel values,
  and row-cardinality guidance (when to split by column vs collapse with `*`)
- `references/detection-patterns.md` — C# signatures and tool-agnostic search patterns for
  SQL, connection strings, API calls, file I/O, SFTP, SharePoint, and email; source-vs-destination
  rules for API flows; when to read a whole file directly instead of searching it
- `references/notes-guidance.md` — checklist of what belongs in `notes`, with good/bad examples

## Scripts

All scripts are PowerShell (Windows PowerShell 5.1 compatible; also run under PowerShell 7+
via `pwsh`). `scripts/DataMap.Common.ps1` is a shared helper library dot-sourced by the other
four — don't invoke it directly.

- `scripts/New-DataMapEntry.ps1` — Pass 1: append one row (named parameters) or a batch
  (`-FromJson <file>`, JSON array of row objects) to a JSONL file. Validates before writing;
  batch mode is all-or-nothing.
- `scripts/Test-DataMapJsonl.ps1` — Pass 2 and Pass 4 gate: validates every line has exactly
  the ten required keys with no blank values (aside from `notes`). Prints a JSON result and
  exits 0/1.
- `scripts/Set-DataMapNotes.ps1` — Pass 3: sets `notes` on one line (`-LineNumber`) or a batch
  (`-Updates <file>`) without touching any other line or field. Optional `-ExpectSrcTbl`/
  `-ExpectDstTbl` guard against editing the wrong row.
- `scripts/ConvertTo-DataMapCsv.ps1` — Final pass: validates then converts JSONL to a
  deterministic RFC 4180 CSV (fixed column order, CRLF, UTF-8 with BOM). `-Sort` for
  canonical row order.
