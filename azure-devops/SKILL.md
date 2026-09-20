---
name: azure-devops
description: Help agents perform common Azure DevOps tasks for work items, pull requests, and pipelines using reliable CLI and REST workflows.
compatibility: Requires Windows PowerShell 5.1 or PowerShell 7+ (pwsh). No other runtime is needed.
---

# azure-devops

## Purpose
Use Azure DevOps tools and APIs to help with common engineering workflow tasks such as managing work items, inspecting and acting on pull requests, and reviewing or queueing pipeline runs.

## Scope
This skill covers:
- Azure DevOps authentication and CLI setup
- Work item creation, updates, queries, and links
- Pull request inspection and common PR actions
- Pipeline listing, run inspection, and run queueing
- Guidance on when to use Azure DevOps CLI versus REST API

## Out of scope
This version does not cover:
- Wiki operations
- Artifacts or package feeds
- Release management
- Test plans
- Custom reporting or dashboards
- General git tasks outside Azure DevOps-specific workflows

## When to use
Use this skill when a task requires interacting with Azure DevOps work items, pull requests, or pipelines, or when an agent needs help choosing between the Azure DevOps CLI and REST API for a supported task.

## Required environment
Prefer these environment variables as the default contract for scripts in this skill:
- `ADO_PAT`: Personal Access Token for Azure DevOps
- `ADO_URL`: Azure DevOps organization or collection URL, for example `https://dev.azure.com/my-org` or `https://ado.contoso.mil/tfs/DefaultCollection`
- `ADO_PROJECT`: Default Azure DevOps project name
- `ADO_REPO`: Optional default repository name for pull request operations

Scripts may also accept explicit parameters to override environment values.

## Running the scripts
The scripts are PowerShell (`.ps1`) and run on Windows PowerShell 5.1 or PowerShell 7+. Call them with `-File` and named parameters:

```powershell
pwsh -File scripts/work-item-get.ps1 -Id 48520
powershell -File scripts\work-item-get.ps1 -Id 48520     # Windows PowerShell 5.1
```

- Parameters are PascalCase (`-Id`, `-Project`, `-Output`). Quote values that contain spaces; a value may start with `-` or contain newlines.
- Options that used to repeat take a quoted, comma-separated list instead: `-Field "A=1,B=2"`, `-Repo "A,B"`. Quote it so it arrives as one string from any shell. A `-Field` value that itself contains a comma is fine as long as the text after the comma does not look like `NAME=`.
- A missing required parameter exits with code 2; a handled failure prints a JSON `error` and exits with code 1.
- Via `run_skill_script`, use the script name `scripts/<name>.ps1` and pass the parameters as a string array, for example `["-Id", "48520"]`.

## Backend strategy
Scripts should support a consistent backend selection rule:
- `auto`: prefer Azure DevOps CLI when available and suitable, otherwise fall back to REST
- `cli`: require Azure DevOps CLI and fail if it is unavailable
- `rest`: call Azure DevOps REST APIs directly

Use the CLI when it provides clear support for the requested operation. Use REST when:
- the Azure CLI is unavailable
- the Azure DevOps extension is unavailable
- the CLI lacks the needed operation or option
- pull request thread or comment behavior is easier or more reliable through REST
- the environment uses Azure DevOps Server/on-prem collection URLs where direct REST calls are the more dependable path

## Common parameters
Use a shared parameter surface across scripts where relevant:
- `-Org <url>`: Azure DevOps organization or collection URL
- `-Project <name>`: Azure DevOps project name
- `-Repo <name>`: repository name for pull request operations
- `-Backend <auto|cli|rest>`: backend selection mode
- `-Output <json|table|tsv>`: output format, default `json`
- `-Verbose`: include backend and request detail in output or logs

## Output conventions
For v1, scripts should aim to:
- return structured JSON by default
- include the most important identifiers in output, such as work item ID, pull request ID, pipeline ID, run ID, and web URL when available
- emit clear error messages that identify whether setup, auth, backend selection, or Azure DevOps API behavior caused the failure
- keep output stable enough for one script result to feed another step

JSON output is pure ASCII (non-ASCII text is `\u`-escaped), so it survives any console code page; `table` and `tsv` print the text as-is.

## Available scripts

- Foundation: `check-ado-prereqs.ps1`, `show-ado-context.ps1`
- Work items: `work-item-get.ps1`, `work-item-query.ps1`, `work-item-create.ps1`, `work-item-update.ps1`, `work-item-delete.ps1`, `work-item-comment.ps1`, `work-item-comment-list.ps1`
- Repositories and code search: `repo-list.ps1`, `code-search.ps1`
- Pull requests: `pr-list.ps1`, `pr-get.ps1`, `pr-comment.ps1`
- Pipelines: `pipeline-runs.ps1`

Full parameter references and examples for each script are in `references/`: `references/foundation.md`, `references/work-items.md`, `references/repositories.md`, `references/pull-requests.md`, and `references/pipelines.md`. Work item linking and attachment support are not yet implemented.
