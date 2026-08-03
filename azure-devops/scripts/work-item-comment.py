#!/usr/bin/env python3
"""Add a comment to an Azure DevOps work item via REST."""

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
        description="Add a comment to an Azure DevOps work item"
    )
    add_common_arguments(parser)
    parser.add_argument("--id", type=int, required=True, help="Work item ID")
    parser.add_argument("--comment", required=True, help="Comment text to add")
    return parser


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    requested_comment: str,
    verbose: bool,
) -> Dict[str, Any]:
    comment_data = response["data"] or {}
    payload: Dict[str, Any] = {
        "operation": "work-item-comment",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {
            "id": comment_data.get("workItemId"),
            "comment": requested_comment,
        },
        "comment": comment_data,
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
                "work-item-comment.py currently supports only the REST backend"
            )

        response = ado_rest_request(
            context,
            method="POST",
            project=context.get("project"),
            path=f"_apis/wit/workItems/{args.id}/comments",
            body={"text": args.comment},
            api_version="7.1-preview.4",
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            requested_comment=args.comment,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
