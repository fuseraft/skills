#!/usr/bin/env python3
"""List Azure DevOps pull requests via REST."""

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


PR_STATUSES = ("all", "active", "completed", "abandoned")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="List Azure DevOps pull requests")
    add_common_arguments(parser, include_repo=True)
    parser.add_argument("--status", choices=PR_STATUSES, default="active", help="Pull request status filter")
    parser.add_argument("--creator-id", help="Filter by creator identity GUID")
    parser.add_argument("--reviewer-id", help="Filter by reviewer identity GUID")
    parser.add_argument("--source-branch", help="Filter by source branch name")
    parser.add_argument("--target-branch", help="Filter by target branch name")
    parser.add_argument("--top", type=int, default=25, help="Maximum number of pull requests to return")
    parser.add_argument("--skip", type=int, default=0, help="Number of pull requests to skip")
    return parser


def normalize_status(status: str) -> str | None:
    return None if status == "all" else status


def build_query(args: argparse.Namespace) -> Dict[str, Any]:
    query: Dict[str, Any] = {
        "$top": args.top,
        "$skip": args.skip,
        "searchCriteria.status": normalize_status(args.status),
        "searchCriteria.creatorId": args.creator_id,
        "searchCriteria.reviewerId": args.reviewer_id,
        "searchCriteria.sourceRefName": args.source_branch,
        "searchCriteria.targetRefName": args.target_branch,
    }
    return query


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    query: Dict[str, Any],
    verbose: bool,
) -> Dict[str, Any]:
    data = response["data"] or {}
    pull_requests = data.get("value", [])
    payload: Dict[str, Any] = {
        "operation": "pr-list",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            include_repo=True,
            verbose=verbose,
        ),
        "request": query,
        "count": data.get("count", len(pull_requests)),
        "pull_requests": pull_requests,
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
        context = resolve_context(args, include_repo=True)
        if not context.get("repo"):
            raise AdoScriptError("Missing required repository name; pass --repo or set ADO_REPO")

        availability = determine_backend_availability(context)
        backend = resolve_backend(args.backend, availability)
        if backend != "rest":
            raise AdoScriptError("pr-list.py currently supports only the REST backend")

        query = build_query(args)
        response = ado_rest_request(
            context,
            method="GET",
            path=f"_apis/git/repositories/{context['repo']}/pullrequests",
            project=context.get("project"),
            query=query,
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            query=query,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
