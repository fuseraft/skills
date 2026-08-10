#!/usr/bin/env python3
"""List Azure DevOps Git repositories via REST."""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict

from _ado_common import (
    AdoScriptError,
    add_common_arguments,
    ado_rest_request,
    build_context_payload,
    determine_backend_availability,
    emit_output,
    resolve_backend,
    resolve_context,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="List Azure DevOps Git repositories")
    add_common_arguments(parser)
    parser.add_argument(
        "--all-projects",
        action="store_true",
        help="List repositories across the whole organization or collection instead of one project",
    )
    parser.add_argument(
        "--include-links",
        action="store_true",
        help="Include the _links block for each repository in the output",
    )
    return parser


def strip_links(repositories: list[Dict[str, Any]], include_links: bool) -> list[Dict[str, Any]]:
    if include_links:
        return repositories
    trimmed: list[Dict[str, Any]] = []
    for repo in repositories:
        item = {key: value for key, value in repo.items() if key != "_links"}
        trimmed.append(item)
    return trimmed


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    scope: str,
    include_links: bool,
    verbose: bool,
) -> Dict[str, Any]:
    data = response["data"] or {}
    repositories = strip_links(data.get("value", []), include_links)
    payload: Dict[str, Any] = {
        "operation": "repo-list",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {"scope": scope},
        "count": data.get("count", len(repositories)),
        "repositories": repositories,
    }
    if verbose:
        payload["rest"] = {
            "status_code": response["status_code"],
            "url": response["url"],
        }
    return payload


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        context = resolve_context(args)
        availability = determine_backend_availability(context)
        backend = resolve_backend(args.backend, availability)
        if backend != "rest":
            raise AdoScriptError("repo-list.py currently supports only the REST backend")

        project = None if args.all_projects else context.get("project")
        if not args.all_projects and not project:
            raise AdoScriptError(
                "Missing required project name; pass --project, set ADO_PROJECT, or use --all-projects"
            )

        response = ado_rest_request(
            context,
            method="GET",
            path="_apis/git/repositories",
            project=project,
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            scope="all-projects" if args.all_projects else project,
            include_links=args.include_links,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
