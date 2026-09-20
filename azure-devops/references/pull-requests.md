# Pull request scripts

Full reference for the pull request scripts in `scripts/`. All scripts currently require `-Backend rest`. `auto` resolves to `rest` only when the Azure CLI (`az`) is not installed, so pass `-Backend rest` on machines that have it. See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/pr-list.ps1`
Lists pull requests for a repository through REST.

#### `scripts/pr-get.ps1`
Retrieves a pull request by ID through REST, with optional threads and linked work item references.

#### `scripts/pr-comment.ps1`
Adds a pull request discussion thread through REST.

Supported comment flags:
- `-Id`
- `-Comment`
- `-Status`
- `-CommentType`
- optional `-FilePath`
- optional `-RightFileStartLine`, `-RightFileStartOffset`, `-RightFileEndLine`, `-RightFileEndOffset`

Example:

```powershell
pwsh -File scripts/pr-comment.ps1 -Backend rest -Repo MyRepo -Id 123 -Comment "Please add a null check here."
```
