# Foundation scripts

Full reference for the foundation scripts in `scripts/`. See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/check-ado-prereqs.ps1`
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
pwsh -File scripts/check-ado-prereqs.ps1 -Output json
pwsh -File scripts/check-ado-prereqs.ps1 -Org https://ado.contoso.mil/tfs/DefaultCollection -Project MyProject -Backend rest -Output table
```

#### `scripts/show-ado-context.ps1`
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
pwsh -File scripts/show-ado-context.ps1 -Output json
pwsh -File scripts/show-ado-context.ps1 -Org https://ado.contoso.mil/tfs/DefaultCollection -Project MyProject -Repo MyRepo -Backend auto -Verbose -Output table
```
