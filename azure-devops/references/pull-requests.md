# Pull request scripts

Full reference for the pull request scripts in `scripts/`. All scripts currently require `--backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/pr-list.py`
Lists pull requests for a repository through REST.

#### `scripts/pr-get.py`
Retrieves a pull request by ID through REST, with optional threads and linked work item references.

#### `scripts/pr-comment.py`
Adds a pull request discussion thread through REST.

Supported comment flags:
- `--id`
- `--comment`
- `--status`
- `--comment-type`
- optional `--file-path`
- optional `--right-file-start-line`, `--right-file-start-offset`, `--right-file-end-line`, `--right-file-end-offset`

Example:

```powershell
python scripts/pr-comment.py --backend rest --repo MyRepo --id 123 --comment "Please add a null check here."
```
