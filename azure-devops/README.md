# Azure DevOps Skill

This skill provides a narrow v1 surface for interacting with Azure DevOps work items, pull requests, and pipelines. It is designed to work in environments where Azure DevOps may be hosted in the cloud or on-premises, including Azure DevOps Server deployments in GCC High-style environments.

## Current focus

This version of the skill focuses on:
- authentication and context resolution
- work item operations
- pull request inspection and common actions
- pipeline inspection and queueing
- choosing between Azure DevOps CLI and REST backends

This version does not currently target:
- wiki operations
- package feeds or artifacts
- releases
- test plans
- dashboards or reporting

## Environment

The scripts use the following environment variables by default:
- `ADO_URL` - Azure DevOps organization URL or collection URL
- `ADO_PROJECT` - Azure DevOps project name
- `ADO_PAT` - Personal Access Token used for REST-based calls
- `ADO_REPO` - optional default repository name for repo-specific scripts

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

## Common flags

The foundation scripts currently support:
- `--org` - Azure DevOps organization or collection URL
- `--project` - Azure DevOps project name
- `--repo` - optional repository name for repo-aware scripts
- `--backend auto|cli|rest`
- `--output json|table|tsv`
- `--verbose`

Command-line values override environment variables.

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

## Current scripts

### Foundation

See [`references/foundation.md`](references/foundation.md) for the full reference: `check-ado-prereqs.py`, `show-ado-context.py`.

### Work items

See [`references/work-items.md`](references/work-items.md) for the full reference: `work-item-get.py`, `work-item-query.py`, `work-item-comment.py`, `work-item-comment-list.py`, `work-item-create.py`, `work-item-update.py`.

### Repositories and code search

See [`references/repositories.md`](references/repositories.md) for the full reference: `repo-list.py`, `code-search.py`.

### Pull requests

See [`references/pull-requests.md`](references/pull-requests.md) for the full reference: `pr-list.py`, `pr-get.py`, `pr-comment.py`.

### Pipelines

See [`references/pipelines.md`](references/pipelines.md) for the full reference: `pipeline-runs.py`.

## Expected next scripts

Pipeline-related work (`scripts/pipeline-list.py`, `scripts/pipeline-run-queue.py`) is deprioritized for now. Possible future additions include:
- `scripts/work-item-link.py` for creating relationships between work items
- `scripts/work-item-attach.py` for attaching files to work items
- `scripts/pr-attach.py` or similar attachment support for pull requests

## Usage notes

- Prefer `--backend rest` when working in tightly controlled on-prem environments unless CLI support is known to be available and correct.
- Keep `ADO_PAT` out of logs, screenshots, and committed files.
- If a PAT is currently stored in a local `.env` file, consider rotating it if it is active and was exposed unintentionally.

## Development notes

This skill currently implements the shared helper, foundation scripts, and REST-first scripts for work items, pull requests, repository listing, code search, and pipeline run listing (see "Current scripts" above). The `--backend cli` option is accepted by all scripts but not yet implemented; every script currently requires `--backend rest` (or `auto`, which resolves to `rest`).
