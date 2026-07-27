#!/usr/bin/env python3
"""Run a WIQL query against Azure DevOps work items."""

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
    require_context_value,
    resolve_backend,
    resolve_context,
)


DEFAULT_TOP = 50


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run a WIQL query against Azure DevOps work items"
    )
    add_common_arguments(parser)
    parser.add_argument(
        "--wiql",
        required=True,
        help="WIQL query text to execute",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=DEFAULT_TOP,
        help=f"Maximum number of work item references to request (default: {DEFAULT_TOP})",
    )
    parser.add_argument(
        "--time-precision",
        action="store_true",
        help="Enable timePrecision for WIQL execution",
    )
    return parser


def extract_work_item_ids(data: Dict[str, Any]) -> List[int]:
    refs = data.get("workItems") or []
    ids: List[int] = []
    for item in refs:
        work_item_id = item.get("id")
        if isinstance(work_item_id, int):
            ids.append(work_item_id)
    return ids


def run_rest(args: argparse.Namespace) -> Dict[str, Any]:
    context = resolve_context(args)
    project = require_context_value(context, "project", "project name")

    wiql_response = ado_rest_request(
        context,
        method="POST",
        path="_apis/wit/wiql",
        project=project,
        query={
            "$top": args.top,
            "timePrecision": "true" if args.time_precision else None,
        },
        body={"query": args.wiql},
    )

    data = wiql_response["data"] or {}
    ids = extract_work_item_ids(data)

    payload: Dict[str, Any] = {
        "operation": "work-item-query",
        "query": {
            "wiql": args.wiql,
            "top": args.top,
            "time_precision": args.time_precision,
        },
        "count": len(ids),
        "work_item_ids": ids,
        "wiql_result": data,
    }

    if args.verbose and ids:
        fields = [
            "System.Id",
            "System.WorkItemType",
            "System.Title",
            "System.State",
            "System.AssignedTo",
        ]
        batch_response = ado_rest_request(
            context,
            method="GET",
            path="_apis/wit/workitems",
            query={
                "ids": ",".join(str(work_item_id) for work_item_id in ids),
                "fields": ",".join(fields),
            },
        )
        payload["work_items"] = batch_response["data"]

    return payload


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    context = resolve_context(args)
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
            verbose=True if args.verbose else False,
        )
        error_payload["error"] = str(exc)
        emit_output(error_payload, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
