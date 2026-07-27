#!/usr/bin/env python3
"""Get a work item from Azure DevOps via REST."""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, List

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
    parser = argparse.ArgumentParser(description="Get an Azure DevOps work item")
    add_common_arguments(parser)
    parser.add_argument("--id", type=int, required=True, help="Work item ID")
    parser.add_argument(
        "--fields",
        help="Comma-separated field reference names to include, for example System.Id,System.Title,System.State",
    )
    parser.add_argument(
        "--expand",
        choices=("all", "fields", "links", "relations", "none"),
        default="none",
        help="Expand related work item data in the REST response",
    )
    return parser


def parse_fields(raw_fields: str | None) -> List[str]:
    if not raw_fields:
        return []
    return [field.strip() for field in raw_fields.split(",") if field.strip()]


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    requested_fields: List[str],
    requested_expand: str,
    verbose: bool,
) -> Dict[str, Any]:
    work_item = response["data"]
    payload: Dict[str, Any] = {
        "operation": "work-item-get",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {
            "id": work_item.get("id"),
            "fields": requested_fields,
            "expand": requested_expand,
        },
        "work_item": work_item,
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
            raise AdoScriptError("work-item-get.py currently supports only the REST backend")

        fields = parse_fields(args.fields)
        query: Dict[str, Any] = {}
        if fields:
            query["fields"] = ",".join(fields)
        if args.expand != "none":
            query["$expand"] = args.expand

        response = ado_rest_request(
            context,
            method="GET",
            path=f"_apis/wit/workitems/{args.id}",
            query=query,
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            requested_fields=fields,
            requested_expand=args.expand,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
