# Work item scripts

Full reference for the work item scripts in `scripts/`. All scripts currently require `--backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/work-item-get.py`
Retrieves a work item by ID through REST.

#### `scripts/work-item-query.py`
Executes a WIQL query and returns matching work item IDs, with optional verbose expansion.

#### `scripts/work-item-comment.py`
Adds a comment to an existing work item through REST.

#### `scripts/work-item-comment-list.py`
Fetches comments from an existing work item through REST.

Supported flags:
- `--id`
- `--top` - maximum number of comments to return
- `--order <asc|desc>` - sort by creation date
- `--continuation-token` - page through results using the token from a previous response

Example:

```powershell
python scripts/work-item-comment-list.py --backend rest --id 48520 --order desc --output table
```

#### `scripts/work-item-update.py`
Updates an existing work item through REST using Azure DevOps JSON Patch.

Supported update flags:
- `--id`
- `--title`
- `--state`
- `--assigned-to`
- `--description`
- `--acceptance-criteria` - Microsoft.VSTS.Common.AcceptanceCriteria, typically used on User Story/PBI items
- `--repro-steps` - Microsoft.VSTS.TCM.ReproSteps, typically used on Bug items
- `--system-info` - Microsoft.VSTS.TCM.SystemInfo, typically used on Bug items
- repeated `--field NAME=VALUE`

Example:

```powershell
python scripts/work-item-update.py --backend rest --id 48520 --state Active --assigned-to "user@example.com" --field Microsoft.VSTS.Common.Priority=1
python scripts/work-item-update.py --backend rest --id 48521 --repro-steps "1. Do X 2. Observe Y" --system-info "Windows Server 2022, build 20348"
```

#### `scripts/work-item-create.py`
Creates a new work item through REST using Azure DevOps JSON Patch.

Supported create flags:
- `--type`
- `--title`
- `--description`
- `--acceptance-criteria` - Microsoft.VSTS.Common.AcceptanceCriteria; set this on every User Story/PBI item, it does not default to anything
- `--assigned-to`
- repeated `--field NAME=VALUE`

Example:

```powershell
python scripts/work-item-create.py --backend rest --type Bug --title "Example bug" --field Microsoft.VSTS.Common.Priority=1
```

`--description`, `--acceptance-criteria`, `--repro-steps`, and `--system-info` are all HTML
rich-text fields in Azure DevOps — a literal `\n` renders as nothing in the work item UI, so
raw plain text collapses into one run-on block. Pass plain text with real blank lines between
paragraphs and `- `/`* ` for bullet lines; both scripts auto-convert that into `<p>`/`<br>`/`<ul>`
HTML before sending it. If you already have HTML, pass it as-is — text containing `<` is sent
through unchanged.

#### `scripts/work-item-delete.py`
Deletes a work item through REST. Use this to remove a work item created by mistake (for
example, a duplicate or an item created while testing).

Supported flags:
- `--id`
- `--destroy` - permanently destroy the item instead of moving it to the project recycle bin.
  Irreversible; omit this unless you are certain. Without it, the item is soft-deleted and can
  be restored from the recycle bin.

Example:

```powershell
python scripts/work-item-delete.py --backend rest --id 55863
```
