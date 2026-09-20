# Pipeline scripts

Full reference for the pipeline scripts in `scripts/`. All scripts currently require `-Backend rest`. `auto` resolves to `rest` only when the Azure CLI (`az`) is not installed, so pass `-Backend rest` on machines that have it. See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/pipeline-runs.ps1`
Lists Azure DevOps pipeline runs through REST.

Supported flags:
- `-PipelineId` - filter by pipeline ID
- `-Branch` - filter by branch ref, for example `refs/heads/main`
- `-Result` - filter by run result
- `-State` - filter by run state
- `-Top` - maximum number of runs to return (default `25`)
- `-ContinuationToken` - page through results using the token from a previous response

Example:

```powershell
pwsh -File scripts/pipeline-runs.ps1 -Backend rest -PipelineId 12 -Result succeeded -Output table
```
