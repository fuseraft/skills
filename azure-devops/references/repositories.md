# Repository and code search scripts

Full reference for the repository and code search scripts in `scripts/`. All scripts currently require `-Backend rest`. `auto` resolves to `rest` only when the Azure CLI (`az`) is not installed, so pass `-Backend rest` on machines that have it. See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/repo-list.ps1`
Lists Azure DevOps Git repositories through REST.

Supported flags:
- `-AllProjects` - list repositories across the whole organization or collection instead of a single project
- `-IncludeLinks` - include the `_links` block for each repository

Example:

```powershell
pwsh -File scripts/repo-list.ps1 -Backend rest -Output table
pwsh -File scripts/repo-list.ps1 -Backend rest -AllProjects -Output json
```

#### `scripts/code-search.ps1`
Searches code across repositories through the Azure DevOps Code Search REST API.

Supported flags:
- `-Text <query>` (required), e.g. `myFunction` or `ext:cs myFunction`
- `-Repo <name>[,<name>...]` to limit results to one or more repositories
- `-Path <path>[,<path>...]` to limit results to a repository-relative path prefix
- `-Branch <name>[,<name>...]` to limit results to a branch
- `-Extension <ext>[,<ext>...]` to limit results to a file extension
- `-Top <count>` and `-Skip <count>` for paging
- `-IncludeFacets` to include facet counts in the response

Note: this requires the Code Search extension/feature to be installed and enabled for the organization or collection. On Azure DevOps Services (cloud), the search API is hosted on a dedicated `almsearch.dev.azure.com` host; the skill resolves this automatically. On Azure DevOps Server / on-prem collections, the same collection host is used.

Example:

```powershell
pwsh -File scripts/code-search.ps1 -Backend rest -Text "ext:cs myFunction" -Repo MyRepo -Output table
```
