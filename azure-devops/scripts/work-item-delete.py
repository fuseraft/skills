#!/usr/bin/env python3
"""Delete an Azure DevOps work item via REST."""

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
    parser = argparse.ArgumentParser(description="Delete an Azure DevOps work item")
    add_common_arguments(parser)
    parser.add_argument("--id", type=int, required=True, help="Work item ID")
    parser.add_argument(
        "--destroy",
        action="store_true",
        help=(
            "Permanently destroy the work item instead of moving it to the project "
            "recycle bin. Irreversible — omit this unless you are certain."
        ),
    )
    return parser


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    work_item_id: int,
    destroy: bool,
    verbose: bool,
) -> Dict[str, Any]:
    data = response["data"] or {}
    resource = data.get("resource") or {}
    payload: Dict[str, Any] = {
        "operation": "work-item-delete",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {"id": work_item_id, "destroy": destroy},
        "work_item": {
            "id": data.get("id", work_item_id),
            "type": data.get("type"),
            "title": data.get("name"),
            "project": data.get("project"),
            "deleted_date": data.get("deletedDate"),
            "deleted_by": data.get("deletedBy"),
            "permanently_destroyed": destroy,
            "recycle_bin_url": None if destroy else data.get("url"),
            "fields": resource.get("fields"),
        },
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
                "work-item-delete.py currently supports only the REST backend"
            )

        response = ado_rest_request(
            context,
            method="DELETE",
            path=f"_apis/wit/workitems/{args.id}",
            project=context.get("project"),
            query={"destroy": "true"} if args.destroy else None,
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            work_item_id=args.id,
            destroy=args.destroy,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
