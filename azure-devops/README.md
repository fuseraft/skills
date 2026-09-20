# Azure DevOps Skill

This skill provides a narrow v1 surface for interacting with Azure DevOps work items, pull requests, and pipelines. It is designed to work in environments where Azure DevOps may be hosted in the cloud or on-premises, including Azure DevOps Server deployments in GCC High-style environments.

## Requirements

The scripts are PowerShell and run on Windows PowerShell 5.1 or PowerShell 7+ (`pwsh`). Nothing else is required: HTTP, JSON, and TLS come from the .NET runtime that PowerShell already ships with.

```powershell
pwsh -File scripts/check-ado-prereqs.ps1
powershell -File scripts\check-ado-prereqs.ps1      # Windows PowerShell 5.1
```

Call scripts with `-File` and named parameters. Quote values that contain spaces. A value may start with `-` or span several lines.

Options that repeat in other CLIs take a comma-separated list here. Quote the list so it reaches the script as one string from any shell (PowerShell, cmd, bash, CI), because `-File` does not build arrays:

```powershell
pwsh -File scripts/work-item-update.ps1 -Id 48520 -Field "Microsoft.VSTS.Common.Priority=1,System.Tags=a; b"
pwsh -File scripts/code-search.ps1 -Text "myFunction" -Repo "RepoOne,RepoTwo"
```

For `-Field`, the list is split on commas only when every piece looks like `NAME=VALUE`, so a single value that contains a comma (`-Field "System.Title=Fix login, then logout"`) is left intact. For the code-search filters (`-Repo`, `-Path`, `-Branch`, `-Extension`) every comma splits.

## Current focus

This version of the skill focuses on:
- authentication and context resolution
- work item operations
- pull request inspection and common actions
- pipeline run inspection (listing and filtering runs)
- choosing between Azure DevOps CLI and REST backends

This version does not currently target:
- wiki operations
- package feeds or artifacts
- releases
- queueing pipeline runs or listing pipeline definitions
- test plans
- dashboards or reporting

## Environment

The scripts use the following environment variables by default:
- `ADO_URL` - Azure DevOps organization URL or collection URL
- `ADO_PROJECT` - Azure DevOps project name
- `ADO_PAT` - Personal Access Token used for REST-based calls
- `ADO_REPO` - optional default repository name for repo-specific scripts

If the variables are not set, the scripts read `KEY=VALUE` lines from a `.env` file in the skill directory, or else in the current directory. Variables already set in the environment always win.

Examples:

Cloud-hosted Azure DevOps:
- `https://dev.azure.com/your-org`

On-prem or Azure DevOps Server style:
- `https://ado.contoso.mil/tfs/DefaultCollection`
- `https://azdo.example.local/CollectionName`

For this skill, `ADO_URL` should be the top-level organization or collection URL, not a project URL.

## Backend model

The scripts support three backend modes:
- `auto` - prefer CLI when it is usable, otherwise use REST when possible
- `cli` - require Azure CLI support
- `rest` - require REST support

### CLI backend

CLI mode depends on:
- `az` being installed and on `PATH`
- the Azure DevOps extension being available
- compatible command coverage for the requested operation

### REST backend

REST mode depends on:
- a valid `ADO_URL`
- `ADO_PROJECT` for project-scoped operations
- `ADO_PAT`

In many on-prem or GCC High-style environments, REST is the more dependable default because:
- the Azure DevOps CLI may not be installed
- some CLI features are incomplete for the task
- Server deployments often benefit from direct URL and PAT control

## Common parameters

The scripts share these parameters where they apply:
- `-Org` - Azure DevOps organization or collection URL
- `-Project` - Azure DevOps project name
- `-Repo` - optional repository name for repo-aware scripts
- `-Backend auto|cli|rest`
- `-Output json|table|tsv`
- `-Verbose`

Parameter values override environment variables.

## URL guidance for on-prem and GCC High-style deployments

Do not assume `dev.azure.com`.

This skill treats any valid HTTP or HTTPS host outside the standard Azure DevOps cloud hosts as a server/on-prem deployment. That means URLs like these are expected to work for context resolution:
- `https://ado.contoso.mil/tfs/DefaultCollection`
- `https://teamdevops.agency.ic/Collection`
- `https://azdo.internal.example/DefaultCollection`

The scripts currently classify URLs into:
- `cloud`
- `server`
- `unknown`

Classification is informational. Backend selection still depends on actual prerequisites.

## Output conventions

The scripts are intended to emit structured output that is easy for an agent to consume.

Current formats:
- `json` - best for automation
- `table` - readable summary output
- `tsv` - flat values when appropriate

Where possible, scripts should return:
- `ok`
- resolved context
- backend information
- diagnostics or error details when a backend cannot be used

JSON output is pure ASCII (non-ASCII text is `\u`-escaped), so it is safe on any console code page. `table` and `tsv` print text as-is and can garble non-ASCII characters on a legacy OEM code page.

## Current scripts

### Foundation

See [`references/foundation.md`](references/foundation.md) for the full reference: `check-ado-prereqs.ps1`, `show-ado-context.ps1`.

### Work items

See [`references/work-items.md`](references/work-items.md) for the full reference: `work-item-get.ps1`, `work-item-query.ps1`, `work-item-comment.ps1`, `work-item-comment-list.ps1`, `work-item-create.ps1`, `work-item-update.ps1`.

### Repositories and code search

See [`references/repositories.md`](references/repositories.md) for the full reference: `repo-list.ps1`, `code-search.ps1`.

### Pull requests

See [`references/pull-requests.md`](references/pull-requests.md) for the full reference: `pr-list.ps1`, `pr-get.ps1`, `pr-comment.ps1`.

### Pipelines

See [`references/pipelines.md`](references/pipelines.md) for the full reference: `pipeline-runs.ps1`.

## Expected next scripts

Pipeline-related work (`scripts/pipeline-list.ps1`, `scripts/pipeline-run-queue.ps1`) is deprioritized for now. Possible future additions include:
- `scripts/work-item-link.ps1` for creating relationships between work items
- `scripts/work-item-attach.ps1` for attaching files to work items
- `scripts/pr-attach.ps1` or similar attachment support for pull requests

## Usage notes

- Prefer `-Backend rest` when working in tightly controlled on-prem environments unless CLI support is known to be available and correct.
- Keep `ADO_PAT` out of logs, screenshots, and committed files.
- If a PAT is currently stored in a local `.env` file, consider rotating it if it is active and was exposed unintentionally.

## Development notes

This skill currently implements the shared helper (`scripts/_ado_common.ps1`), foundation scripts, and REST-first scripts for work items, pull requests, repository listing, code search, and pipeline run listing (see "Current scripts" above). The `-Backend cli` option is accepted by all scripts but not yet implemented; every script currently requires `-Backend rest`, and `-Backend auto` resolves to `rest` for them even when the Azure CLI (`az`) is installed. Only `check-ado-prereqs.ps1` and `show-ado-context.ps1` report `cli` as the preferred backend when `az` is on `PATH`, because they describe the environment rather than run an operation.

The scripts target Windows PowerShell 5.1 as well as PowerShell 7+, so they avoid newer syntax (ternary, `??`, `ConvertFrom-Json -AsHashtable`) and are pure ASCII, since 5.1 reads BOM-less UTF-8 files as ANSI. JSON is produced and parsed by `_ado_common.ps1` rather than `ConvertTo-Json`/`ConvertFrom-Json`, whose behavior differs across versions.
