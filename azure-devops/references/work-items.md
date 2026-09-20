# Work item scripts

Full reference for the work item scripts in `scripts/`. All scripts currently require `-Backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/work-item-get.ps1`
Retrieves a work item by ID through REST.

#### `scripts/work-item-query.ps1`
Executes a WIQL query and returns matching work item IDs, with optional verbose expansion.

#### `scripts/work-item-comment.ps1`
Adds a comment to an existing work item through REST.

#### `scripts/work-item-comment-list.ps1`
Fetches comments from an existing work item through REST.

Supported flags:
- `-Id`
- `-Top` - maximum number of comments to return
- `-Order <asc|desc>` - sort by creation date
- `-ContinuationToken` - page through results using the token from a previous response

Example:

```powershell
pwsh -File scripts/work-item-comment-list.ps1 -Backend rest -Id 48520 -Order desc -Output table
```

#### `scripts/work-item-update.ps1`
Updates an existing work item through REST using Azure DevOps JSON Patch.

Supported update flags:
- `-Id`
- `-Title`
- `-State`
- `-AssignedTo`
- `-Description`
- `-AcceptanceCriteria` - Microsoft.VSTS.Common.AcceptanceCriteria, typically used on User Story/PBI items
- `-ReproSteps` - Microsoft.VSTS.TCM.ReproSteps, typically used on Bug items
- `-SystemInfo` - Microsoft.VSTS.TCM.SystemInfo, typically used on Bug items
- `-Field NAME=VALUE[,NAME=VALUE...]` - arbitrary field reference names

Example:

```powershell
pwsh -File scripts/work-item-update.ps1 -Backend rest -Id 48520 -State Active -AssignedTo "user@example.com" -Field Microsoft.VSTS.Common.Priority=1
pwsh -File scripts/work-item-update.ps1 -Backend rest -Id 48521 -ReproSteps "1. Do X 2. Observe Y" -SystemInfo "Windows Server 2022, build 20348"
```

#### `scripts/work-item-create.ps1`
Creates a new work item through REST using Azure DevOps JSON Patch.

Supported create flags:
- `-Type`
- `-Title`
- `-Description`
- `-AcceptanceCriteria` - Microsoft.VSTS.Common.AcceptanceCriteria; set this on every User Story/PBI item, it does not default to anything
- `-AssignedTo`
- `-Field NAME=VALUE[,NAME=VALUE...]` - arbitrary field reference names

Example:

```powershell
pwsh -File scripts/work-item-create.ps1 -Backend rest -Type Bug -Title "Example bug" -Field Microsoft.VSTS.Common.Priority=1
```

`-Description`, `-AcceptanceCriteria`, `-ReproSteps`, and `-SystemInfo` are all HTML
rich-text fields in Azure DevOps — a literal `\n` renders as nothing in the work item UI, so
raw plain text collapses into one run-on block. Pass plain text with real blank lines between
paragraphs and `- `/`* ` for bullet lines; both scripts auto-convert that into `<p>`/`<br>`/`<ul>`
HTML before sending it (Windows CRLF line endings are fine). If you already have HTML, pass it as-is — text containing `<` is sent
through unchanged.

#### `scripts/work-item-delete.ps1`
Deletes a work item through REST. Use this to remove a work item created by mistake (for
example, a duplicate or an item created while testing).

Supported flags:
- `-Id`
- `-Destroy` - permanently destroy the item instead of moving it to the project recycle bin.
  Irreversible; omit this unless you are certain. Without it, the item is soft-deleted and can
  be restored from the recycle bin.

Example:

```powershell
pwsh -File scripts/work-item-delete.ps1 -Backend rest -Id 55863
```
