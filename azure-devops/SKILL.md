---
name: azure-devops
description: Help agents perform common Azure DevOps tasks for work items, pull requests, and pipelines using reliable CLI and REST workflows.
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

Scripts may also accept explicit command-line flags to override environment values.

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

## Common flags
Use a shared argument surface across scripts where relevant:
- `--org <url>`: Azure DevOps organization or collection URL
- `--project <name>`: Azure DevOps project name
- `--repo <name>`: repository name for pull request operations
- `--backend <auto|cli|rest>`: backend selection mode
- `--output <json|table|tsv>`: output format, default `json`
- `--verbose`: include backend and request detail in output or logs

## Output conventions
For v1, scripts should aim to:
- return structured JSON by default
- include the most important identifiers in output, such as work item ID, pull request ID, pipeline ID, run ID, and web URL when available
- emit clear error messages that identify whether setup, auth, backend selection, or Azure DevOps API behavior caused the failure
- keep output stable enough for one script result to feed another step

## Proposed v1 script catalog

### Foundation scripts

#### `scripts/check-ado-prereqs`
Purpose:
- verify whether Azure DevOps CLI mode or REST mode is usable

Suggested arguments:
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- check whether `az` is installed
- check whether the Azure DevOps extension is installed when CLI mode is requested
- check whether required environment variables or overrides are present
- report whether `cli`, `rest`, both, or neither are available

#### `scripts/show-ado-context`
Purpose:
- print the resolved organization, project, repo, and backend mode that other scripts would use

Suggested arguments:
- `--org <url>`
- `--project <name>`
- `--repo <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- resolve values from flags first, then environment
- avoid printing secrets
- indicate whether auth appears configured without echoing the token

### Work item scripts

#### `scripts/work-item-get`
Purpose:
- retrieve a work item by ID

Suggested arguments:
- `--id <work-item-id>`
- `--org <url>`
- `--project <name>`
- `--fields <comma-separated-field-list>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- return the work item with selected fields when requested
- include the work item URL when available

#### `scripts/work-item-query`
Purpose:
- query work items using WIQL or a constrained preset surface

Suggested arguments:
- `--wiql <query>`
- `--preset <assigned-to-me|my-active|by-state>`
- `--state <state>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- allow direct WIQL for advanced use
- optionally support a few safe presets for common tasks
- return matched work item IDs and summary fields

#### `scripts/work-item-comment`
Purpose:
- add a comment to an existing work item

Suggested arguments:
- `--id <work-item-id>`
- `--comment <text>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- create a new work item comment through REST
- return the work item ID, comment ID, comment version, and comment text when available

#### `scripts/work-item-create`
Purpose:
- create a work item with a small, practical field surface

Suggested arguments:
- `--type <Bug|Task|User Story|...>`
- `--title <text>`
- `--description <text>`
- `--area-path <path>`
- `--iteration-path <path>`
- `--assigned-to <identity>`
- repeated `--field <name=value>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- create the work item
- return the created ID, type, title, state, and URL

#### `scripts/work-item-update`
Purpose:
- update one work item using explicit fields or a few convenience flags

Suggested arguments:
- `--id <work-item-id>`
- repeated `--field <name=value>`
- `--state <state>`
- `--reason <text>`
- `--assigned-to <identity>`
- `--title <text>`
- `--description <text>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- update the target work item
- return the updated item and changed fields when available

#### `scripts/work-item-link`
Purpose:
- create a relationship between two work items

Suggested arguments:
- `--source-id <work-item-id>`
- `--target-id <work-item-id>`
- `--link-type <relation-name>`
- `--comment <text>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- add the requested link relation
- return both work item IDs and relation details

### Pull request scripts

#### `scripts/pr-list`
Purpose:
- list pull requests with a few useful filters

Suggested arguments:
- `--repo <name>`
- `--status <active|completed|abandoned|all>`
- `--creator <identity>`
- `--reviewer <identity>`
- `--source-branch <name>`
- `--target-branch <name>`
- `--top <count>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- return pull request summaries with IDs, titles, status, creator, branches, and URLs

#### `scripts/pr-get`
Purpose:
- retrieve one pull request in detail

Suggested arguments:
- `--id <pull-request-id>`
- `--repo <name>`
- `--include-reviewers`
- `--include-threads`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- return detailed PR metadata
- optionally include reviewer or thread data if the backend supports it directly

#### `scripts/pr-comment`
Purpose:
- create a pull request comment, usually through REST

Suggested arguments:
- `--id <pull-request-id>`
- `--repo <name>`
- `--comment <text>`
- `--thread-id <thread-id>`
- `--parent-comment-id <comment-id>`
- `--status <active|fixed|wontfix|closed>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- create a new thread when no thread ID is supplied
- add a reply when thread ID is supplied
- return thread ID, comment ID, and PR ID

### Pipeline scripts

#### `scripts/pipeline-list`
Purpose:
- list pipelines in a project

Suggested arguments:
- `--name <filter>`
- `--folder <path>`
- `--top <count>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- return pipeline IDs, names, folders, and URLs when available

#### `scripts/pipeline-runs`
Purpose:
- list recent runs for one pipeline or for the project

Suggested arguments:
- `--pipeline-id <pipeline-id>`
- `--branch <name>`
- `--status <inProgress|completed|all>`
- `--result <succeeded|failed|canceled|all>`
- `--top <count>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- return run IDs, pipeline IDs, states, results, source branches, queue times, and URLs

#### `scripts/pipeline-run-queue`
Purpose:
- queue a pipeline run with optional branch and variables

Suggested arguments:
- `--pipeline-id <pipeline-id>`
- `--branch <name>`
- `--commit <sha>`
- repeated `--variable <name=value>`
- repeated `--parameter <name=value>`
- `--org <url>`
- `--project <name>`
- `--backend <auto|cli|rest>`
- `--output <json|table|tsv>`

Expected behavior:
- queue a run
- return the run ID, pipeline ID, initial state, and URL

## Recommended implementation order
Start with this sequence:
1. `scripts/check-ado-prereqs`
2. `scripts/show-ado-context`
3. `scripts/work-item-get`
4. `scripts/work-item-query`
5. `scripts/pr-list`
6. `scripts/pipeline-runs`
7. `scripts/pipeline-run-queue`

This order establishes the shared setup contract first, then adds one useful read path per supported area before write operations.
