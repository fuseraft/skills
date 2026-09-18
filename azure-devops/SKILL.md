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

## Available scripts

- Foundation: `check-ado-prereqs.py`, `show-ado-context.py`
- Work items: `work-item-get.py`, `work-item-query.py`, `work-item-create.py`, `work-item-update.py`, `work-item-comment.py`, `work-item-comment-list.py`
- Repositories and code search: `repo-list.py`, `code-search.py`
- Pull requests: `pr-list.py`, `pr-get.py`, `pr-comment.py`
- Pipelines: `pipeline-runs.py`

See `README.md` in this skill directory for full flag reference and examples for each script. Pipeline work beyond `pipeline-runs.py`, work item linking, and attachment support are not yet implemented.
