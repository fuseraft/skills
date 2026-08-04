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

## Current scripts

### Foundation

#### `scripts/check-ado-prereqs.py`
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
python scripts/check-ado-prereqs.py --output json
python scripts/check-ado-prereqs.py --org https://ado.contoso.mil/tfs/DefaultCollection --project MyProject --backend rest --output table
```

#### `scripts/show-ado-context.py`
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
python scripts/show-ado-context.py --output json
python scripts/show-ado-context.py --org https://ado.contoso.mil/tfs/DefaultCollection --project MyProject --repo MyRepo --backend auto --verbose --output table
```

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

### Work items

#### `scripts/work-item-get.py`
Retrieves a work item by ID through REST.

#### `scripts/work-item-query.py`
Executes a WIQL query and returns matching work item IDs, with optional verbose expansion.

#### `scripts/work-item-comment.py`
Adds a comment to an existing work item through REST.

#### `scripts/work-item-update.py`
Updates an existing work item through REST using Azure DevOps JSON Patch.

Supported update flags:
- `--id`
- `--title`
- `--state`
- `--assigned-to`
- `--description`
- repeated `--field NAME=VALUE`

Example:

```powershell
python scripts/work-item-update.py --backend rest --id 48520 --state Active --assigned-to "user@example.com" --field Microsoft.VSTS.Common.Priority=1
```

#### `scripts/work-item-create.py`
Creates a new work item through REST using Azure DevOps JSON Patch.

Supported create flags:
- `--type`
- `--title`
- `--description`
- `--assigned-to`
- repeated `--field NAME=VALUE`

Example:

```powershell
python scripts/work-item-create.py --backend rest --type Bug --title "Example bug" --field Microsoft.VSTS.Common.Priority=1
```

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

## Expected next scripts

The planned v1 script surface includes:
- `scripts/pipeline-list.py`
- `scripts/pipeline-runs.py`
- `scripts/pipeline-run-queue.py`

## Usage notes

- Prefer `--backend rest` when working in tightly controlled on-prem environments unless CLI support is known to be available and correct.
- Keep `ADO_PAT` out of logs, screenshots, and committed files.
- If a PAT is currently stored in a local `.env` file, consider rotating it if it is active and was exposed unintentionally.

## Development notes

At the moment, this repository contains the shared helper and foundation scripts only. The next implementation step is to add read-oriented REST-first scripts for:
- work items
- pull requests
- pipelines

That should provide a stable base before adding write operations.
