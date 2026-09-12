# Worked Example

A small `OrderService` app with four flows, shown from C# source through all four passes to
final CSV. Same four rows referenced in `references/schema.md`'s "Worked shape" section.

## The code

**1. Dapper read from `OrdersDB`, forwarded to an external shipping API**

```csharp
// ShippingService.cs
public async Task NotifyCarrierAsync(int orderId)
{
    var customerId = await _connection.QueryFirstAsync<int>(
        "SELECT CustomerId FROM dbo.Orders WHERE OrderId = @OrderId",
        new { OrderId = orderId });

    await _httpClient.PostAsJsonAsync("/v1/shipments", new { customerId });
    // _httpClient.BaseAddress == https://api.shipping.example.com, set in Startup.cs
}
```

**2. EPPlus read from a file share, bulk-inserted into `OrdersDB`**

```csharp
// CustomerImportJob.cs
using var package = new ExcelPackage(new FileInfo(@"\\fileshare\imports\customers.xlsx"));
var sheet = package.Workbook.Worksheets[0];
// ... reads every column present, header-matched, and passes the whole row through
// to a bulk insert into dbo.Customers with no per-column allowlist.
```

**3. Dapper read from `OrdersDB`, emailed as a nightly summary**

```csharp
// NightlyReportJob.cs
var orders = await _connection.QueryAsync("SELECT * FROM dbo.Orders WHERE OrderDate = @Today", new { Today = DateTime.Today });

var message = new MailMessage();
message.To.Add("ops-team@example.com");
message.Body = BuildSummary(orders); // full row dump, no filtering or masking
_smtpClient.Send(message);
```

**4. External inventory API read, written into `OrdersDB`**

```csharp
// InventorySyncJob.cs
var response = await _httpClient.GetFromJsonAsync<InventoryDto>($"/v2/inventory/{sku}");
// _httpClient.BaseAddress == https://api.partner.example.com

await _connection.ExecuteAsync(
    "UPDATE dbo.InventorySnapshot SET QuantityOnHand = @Qty WHERE Sku = @Sku",
    new { Qty = response.QuantityOnHand, Sku = sku });
```

## Pass 1 — structural JSONL (notes blank)

```json
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"CustomerId","dst_type":"API","dst_name":"https://api.shipping.example.com","dst_tbl":"POST /v1/shipments","dst_col":"N/A","notes":""}
{"name":"OrderService","src_type":"File","src_name":"\\\\fileshare\\imports","src_tbl":"customers.xlsx","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.Customers","dst_col":"*","notes":""}
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"*","dst_type":"Email","dst_name":"Corporate SMTP Relay","dst_tbl":"ops-team@example.com","dst_col":"N/A","notes":""}
{"name":"OrderService","src_type":"API","src_name":"https://api.partner.example.com","src_tbl":"GET /v2/inventory/{sku}","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.InventorySnapshot","dst_col":"QuantityOnHand","notes":""}
```

Produced with, e.g. for row 1:

```bash
pwsh -File scripts/New-DataMapEntry.ps1 -Path orderservice.jsonl \
  -Name "OrderService" -SrcType Database -SrcName "OrdersDB" -SrcTbl "dbo.Orders" -SrcCol "CustomerId" \
  -DstType API -DstName "https://api.shipping.example.com" -DstTbl "POST /v1/shipments" -DstCol "N/A"
```

or all four at once via a batch file passed to `-FromJson`.

Validate: `pwsh -File scripts/Test-DataMapJsonl.ps1 -Path orderservice.jsonl` → `"valid": true`.

## Pass 3 — notes populated

Applied via `scripts/Set-DataMapNotes.ps1`, one line (or one batch) at a time:

```json
[
  { "line": 1, "notes": "Only CustomerId is forwarded; used to correlate the shipment on the carrier side.", "expectDstTbl": "POST /v1/shipments" },
  { "line": 2, "notes": "Read via EPPlus, first worksheet only; header row assumed at row 1. All columns copied 1:1 by header-name match with no allowlist - a new column added to the sheet flows straight into dbo.Customers.", "expectSrcTbl": "customers.xlsx" },
  { "line": 3, "notes": "SELECT * used; sent nightly via a scheduled job with no filtering or masking. Full Orders row (including any PII columns present) reaches the ops-team mailbox as plain text.", "expectDstTbl": "ops-team@example.com" },
  { "line": 4, "notes": "Only QuantityOnHand is persisted from the API response; other fields on InventoryDto are discarded." }
]
```

```bash
pwsh -File scripts/Set-DataMapNotes.ps1 -Path orderservice.jsonl -Updates notes-batch.json
```

Resulting JSONL (final, after Pass 4 re-validation):

```json
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"CustomerId","dst_type":"API","dst_name":"https://api.shipping.example.com","dst_tbl":"POST /v1/shipments","dst_col":"N/A","notes":"Only CustomerId is forwarded; used to correlate the shipment on the carrier side."}
{"name":"OrderService","src_type":"File","src_name":"\\\\fileshare\\imports","src_tbl":"customers.xlsx","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.Customers","dst_col":"*","notes":"Read via EPPlus, first worksheet only; header row assumed at row 1. All columns copied 1:1 by header-name match with no allowlist - a new column added to the sheet flows straight into dbo.Customers."}
{"name":"OrderService","src_type":"Database","src_name":"OrdersDB","src_tbl":"dbo.Orders","src_col":"*","dst_type":"Email","dst_name":"Corporate SMTP Relay","dst_tbl":"ops-team@example.com","dst_col":"N/A","notes":"SELECT * used; sent nightly via a scheduled job with no filtering or masking. Full Orders row (including any PII columns present) reaches the ops-team mailbox as plain text."}
{"name":"OrderService","src_type":"API","src_name":"https://api.partner.example.com","src_tbl":"GET /v2/inventory/{sku}","src_col":"N/A","dst_type":"Database","dst_name":"OrdersDB","dst_tbl":"dbo.InventorySnapshot","dst_col":"QuantityOnHand","notes":"Only QuantityOnHand is persisted from the API response; other fields on InventoryDto are discarded."}
```

## Final CSV

```bash
pwsh -File scripts/ConvertTo-DataMapCsv.ps1 -JsonlPath orderservice.jsonl -CsvPath orderservice.csv
```

Produces a single CRLF-terminated, UTF-8-with-BOM RFC 4180 CSV. Only `notes` values that
actually contain a comma, quote, or newline get quoted — row 2 below does (it has a comma
after "EPPlus"), row 3 doesn't, even though both are long:

```
name,src_type,src_name,src_tbl,src_col,dst_type,dst_name,dst_tbl,dst_col,notes
OrderService,Database,OrdersDB,dbo.Orders,CustomerId,API,https://api.shipping.example.com,POST /v1/shipments,N/A,Only CustomerId is forwarded; used to correlate the shipment on the carrier side.
OrderService,File,\\fileshare\imports,customers.xlsx,N/A,Database,OrdersDB,dbo.Customers,*,"Read via EPPlus, first worksheet only; header row assumed at row 1. All columns copied 1:1 by header-name match with no allowlist - a new column added to the sheet flows straight into dbo.Customers."
OrderService,Database,OrdersDB,dbo.Orders,*,Email,Corporate SMTP Relay,ops-team@example.com,N/A,SELECT * used; sent nightly via a scheduled job with no filtering or masking. Full Orders row (including any PII columns present) reaches the ops-team mailbox as plain text.
OrderService,API,https://api.partner.example.com,GET /v2/inventory/{sku},N/A,Database,OrdersDB,dbo.InventorySnapshot,QuantityOnHand,Only QuantityOnHand is persisted from the API response; other fields on InventoryDto are discarded.
```
