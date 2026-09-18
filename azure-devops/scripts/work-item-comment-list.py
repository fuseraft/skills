#!/usr/bin/env python3
"""List comments on an Azure DevOps work item via REST."""

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
    parser = argparse.ArgumentParser(
        description="List comments on an Azure DevOps work item"
    )
    add_common_arguments(parser)
    parser.add_argument("--id", type=int, required=True, help="Work item ID")
    parser.add_argument(
        "--top",
        type=int,
        help="Maximum number of comments to return",
    )
    parser.add_argument(
        "--order",
        choices=("asc", "desc"),
        help="Sort comments by creation date ascending or descending",
    )
    parser.add_argument(
        "--continuation-token",
        help="Continuation token from a previous response, for paging",
    )
    return parser


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    work_item_id: int,
    verbose: bool,
) -> Dict[str, Any]:
    data = response["data"] or {}
    comments = data.get("comments") or []
    payload: Dict[str, Any] = {
        "operation": "work-item-comment-list",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {
            "id": work_item_id,
        },
        "total_count": data.get("totalCount", len(comments)),
        "count": data.get("count", len(comments)),
        "continuation_token": data.get("continuationToken"),
        "comments": comments,
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
            raise AdoScriptError(
                "work-item-comment-list.py currently supports only the REST backend"
            )

        query: Dict[str, Any] = {}
        if args.top is not None:
            query["$top"] = args.top
        if args.order is not None:
            query["order"] = "createdDate asc" if args.order == "asc" else "createdDate desc"
        if args.continuation_token is not None:
            query["continuationToken"] = args.continuation_token

        response = ado_rest_request(
            context,
            method="GET",
            project=context.get("project"),
            path=f"_apis/wit/workItems/{args.id}/comments",
            query=query,
            api_version="7.1-preview.4",
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            work_item_id=args.id,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
