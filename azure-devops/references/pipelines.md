# Pipeline scripts

Full reference for the pipeline scripts in `scripts/`. All scripts currently require `-Backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

Queueing (starting) a pipeline run and listing pipeline definitions are not implemented.

#### `scripts/pipeline-runs.ps1`
Lists Azure DevOps pipeline runs through REST. It uses the Builds API (`_apis/build/builds`), which returns runs of both YAML and classic pipelines on Azure DevOps Services and Azure DevOps Server. (The Pipelines "Runs - List" API cannot be used for this: it requires a pipeline ID in the path and accepts no filters.)

Supported flags:
- `-PipelineId` - filter by pipeline (build definition) ID
- `-Branch` - filter by branch ref, for example `refs/heads/main`
- `-Result` - filter by run result: `succeeded`, `partiallySucceeded`, `failed`, `canceled`, or `none`
- `-State` - filter by run status: `inProgress`, `completed`, `cancelling`, `postponed`, `notStarted`, or `all`
- `-Top` - maximum number of runs to return (default `25`)
- `-ContinuationToken` - page through results using the `continuation_token` from a previous response

The runs are returned under `runs`, exactly as the Builds API reports them (`id`, `buildNumber`, `status`, `result`, `sourceBranch`, `definition`, and so on). When more results are available the response includes `continuation_token`; it is `null` otherwise.

Example:

```powershell
pwsh -File scripts/pipeline-runs.ps1 -Backend rest -PipelineId 12 -Result succeeded -Output table
```
