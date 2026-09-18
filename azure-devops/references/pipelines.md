# Pipeline scripts

Full reference for the pipeline scripts in `scripts/`. All scripts currently require `--backend rest` (or `auto`, which resolves to `rest`). See the top-level `README.md` for environment variables and common flags shared across all scripts.

#### `scripts/pipeline-runs.py`
Lists Azure DevOps pipeline runs through REST.

Supported flags:
- `--pipeline-id` - filter by pipeline ID
- `--branch` - filter by branch ref, for example `refs/heads/main`
- `--result` - filter by run result
- `--state` - filter by run state
- `--top` - maximum number of runs to return (default `25`)
- `--continuation-token` - page through results using the token from a previous response

Example:

```powershell
python scripts/pipeline-runs.py --backend rest --pipeline-id 12 --result succeeded --output table
```
