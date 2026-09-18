# Repository and code search scripts

Full reference for the repository and code search scripts in `scripts/`. All scripts currently require `--backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/repo-list.py`
Lists Azure DevOps Git repositories through REST.

Supported flags:
- `--all-projects` - list repositories across the whole organization or collection instead of a single project
- `--include-links` - include the `_links` block for each repository

Example:

```powershell
python scripts/repo-list.py --backend rest --output table
python scripts/repo-list.py --backend rest --all-projects --output json
```

#### `scripts/code-search.py`
Searches code across repositories through the Azure DevOps Code Search REST API.

Supported flags:
- `--text <query>` (required), e.g. `myFunction` or `ext:cs myFunction`
- repeated `--repo <name>` to limit results to one or more repositories
- repeated `--path <path>` to limit results to a repository-relative path prefix
- repeated `--branch <name>` to limit results to a branch
- repeated `--extension <ext>` to limit results to a file extension
- `--top <count>` and `--skip <count>` for paging
- `--include-facets` to include facet counts in the response

Note: this requires the Code Search extension/feature to be installed and enabled for the organization or collection. On Azure DevOps Services (cloud), the search API is hosted on a dedicated `almsearch.dev.azure.com` host; the skill resolves this automatically. On Azure DevOps Server / on-prem collections, the same collection host is used.

Example:

```powershell
python scripts/code-search.py --backend rest --text "ext:cs myFunction" --repo MyRepo --output table
```
