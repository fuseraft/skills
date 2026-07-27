#!/usr/bin/env python3
"""Get Azure DevOps pull request details by ID."""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, Optional
from urllib.parse import quote

from _ado_common import (
    AdoScriptError,
    add_common_arguments,
    ado_rest_request,
    build_context_payload,
    determine_backend_availability,
    emit_output,
    require_context_value,
    resolve_backend,
    resolve_context,
)


DEFAULT_TOP_THREADS = 100


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Get Azure DevOps pull request details by ID"
    )
    add_common_arguments(parser, include_repo=True)
    parser.add_argument("--id", required=True, type=int, help="Pull request ID")
    parser.add_argument(
        "--include-threads",
        action="store_true",
        help="Include pull request discussion threads",
    )
    parser.add_argument(
        "--include-work-item-refs",
        action="store_true",
        help="Include linked work item references",
    )
    parser.add_argument(
        "--top-threads",
        type=int,
        default=DEFAULT_TOP_THREADS,
        help=f"Maximum number of threads to request when --include-threads is used (default: {DEFAULT_TOP_THREADS})",
    )
    return parser


def build_pr_path(repo: str, pr_id: int) -> str:
    encoded_repo = quote(repo, safe="")
    return f"_apis/git/repositories/{encoded_repo}/pullRequests/{pr_id}"


def get_threads(context: Dict[str, Optional[str]], repo: str, pr_id: int, top: int) -> Dict[str, Any]:
    return ado_rest_request(
        context,
        method="GET",
        path=build_pr_path(repo, pr_id) + "/threads",
        query={"$top": top},
    )["data"]


def get_work_item_refs(context: Dict[str, Optional[str]], repo: str, pr_id: int) -> Dict[str, Any]:
    return ado_rest_request(
        context,
        method="GET",
        path=build_pr_path(repo, pr_id) + "/workitems",
    )["data"]


def run_rest(args: argparse.Namespace) -> Dict[str, Any]:
    context = resolve_context(args, include_repo=True)
    repo = require_context_value(context, "repo", "repository name")

    pr_response = ado_rest_request(
        context,
        method="GET",
        path=build_pr_path(repo, args.id),
    )

    result: Dict[str, Any] = {
        "operation": "pr-get",
        "repo": repo,
        "pull_request_id": args.id,
        "pull_request": pr_response["data"],
    }

    if args.include_threads:
        result["threads"] = get_threads(context, repo, args.id, args.top_threads)

    if args.include_work_item_refs:
        result["work_item_refs"] = get_work_item_refs(context, repo, args.id)

    return result


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    context = resolve_context(args, include_repo=True)
    availability = determine_backend_availability(context)

    try:
        backend = resolve_backend(args.backend, availability)
        if backend != "rest":
            raise AdoScriptError(
                "This script currently supports only the REST backend"
            )
        payload = build_context_payload(
            context,
            availability=availability,
            requested_backend=args.backend,
            include_repo=True,
            verbose=args.verbose,
        )
        payload["backend"]["resolved"] = backend
        payload["result"] = run_rest(args)
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        error_payload = build_context_payload(
            context,
            availability=availability,
            requested_backend=args.backend,
            include_repo=True,
            verbose=True if args.verbose else False,
        )
        error_payload["error"] = str(exc)
        emit_output(error_payload, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
