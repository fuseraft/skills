# Foundation scripts

Full reference for the foundation scripts in `scripts/`. See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/check-ado-prereqs.py`
Checks whether the environment is ready for CLI and/or REST usage.

What it reports:
- resolved org or collection URL
- project presence
- PAT presence
- Azure CLI presence
- extension status
- URL classification
  - cloud
  - server/on-prem
  - valid/invalid
- requested and resolved backend

Examples:

```powershell
python scripts/check-ado-prereqs.py --output json
python scripts/check-ado-prereqs.py --org https://ado.contoso.mil/tfs/DefaultCollection --project MyProject --backend rest --output table
```

#### `scripts/show-ado-context.py`
Shows the resolved execution context that downstream scripts will use.

What it reports:
- org or collection URL
- project
- optional repo
- auth presence
- deployment classification
- available backends
- resolved backend

Examples:

```powershell
python scripts/show-ado-context.py --output json
python scripts/show-ado-context.py --org https://ado.contoso.mil/tfs/DefaultCollection --project MyProject --repo MyRepo --backend auto --verbose --output table
```
