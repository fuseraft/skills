#!/usr/bin/env python3
"""Create an Azure DevOps work item via REST."""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, List, Tuple
from urllib.parse import quote

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

FIELD_ALIASES = {
    "title": "System.Title",
    "description": "System.Description",
    "assigned_to": "System.AssignedTo",
}

RETURN_FIELDS = [
    "System.WorkItemType",
    "System.Title",
    "System.State",
    "System.AssignedTo",
    "System.Description",
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create an Azure DevOps work item")
    add_common_arguments(parser)
    parser.add_argument(
        "--type",
        required=True,
        help="Work item type, for example Bug, Task, or User Story",
    )
    parser.add_argument("--title", required=True, help="Set System.Title")
    parser.add_argument("--description", help="Set System.Description")
    parser.add_argument("--assigned-to", help="Set System.AssignedTo")
    parser.add_argument(
        "--field",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="Set an arbitrary work item field reference name, for example Microsoft.VSTS.Common.Priority=1",
    )
    return parser


def parse_field_assignment(raw: str) -> Tuple[str, str]:
    if "=" not in raw:
        raise AdoScriptError(
            f"Invalid --field value {raw!r}; expected NAME=VALUE"
        )
    name, value = raw.split("=", 1)
    field_name = name.strip()
    if not field_name:
        raise AdoScriptError(
            f"Invalid --field value {raw!r}; field name cannot be empty"
        )
    return field_name, value


def build_patch_document(args: argparse.Namespace) -> List[Dict[str, Any]]:
    operations: List[Dict[str, Any]] = [
        {"op": "add", "path": "/fields/System.Title", "value": args.title}
    ]

    if args.description is not None:
        operations.append(
            {
                "op": "add",
                "path": "/fields/System.Description",
                "value": args.description,
            }
        )
    if args.assigned_to is not None:
        operations.append(
            {
                "op": "add",
                "path": "/fields/System.AssignedTo",
                "value": args.assigned_to,
            }
        )

    for raw_field in args.field:
        field_name, value = parse_field_assignment(raw_field)
        operations.append(
            {"op": "add", "path": f"/fields/{field_name}", "value": value}
        )

    return operations


def build_requested_fields(args: argparse.Namespace) -> Dict[str, Any]:
    requested: Dict[str, Any] = {
        FIELD_ALIASES["title"]: args.title,
    }
    if args.description is not None:
        requested[FIELD_ALIASES["description"]] = args.description
    if args.assigned_to is not None:
        requested[FIELD_ALIASES["assigned_to"]] = args.assigned_to
    for raw_field in args.field:
        field_name, value = parse_field_assignment(raw_field)
        requested[field_name] = value
    return requested


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    work_item_type: str,
    requested_fields: Dict[str, Any],
    verbose: bool,
) -> Dict[str, Any]:
    work_item = response["data"] or {}
    fields = work_item.get("fields") or {}
    payload: Dict[str, Any] = {
        "operation": "work-item-create",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {
            "type": work_item_type,
            "fields": requested_fields,
        },
        "work_item": {
            "id": work_item.get("id"),
            "rev": work_item.get("rev"),
            "url": work_item.get("url"),
            "fields": fields,
            "summary": {
                "type": fields.get("System.WorkItemType"),
                "title": fields.get("System.Title"),
                "state": fields.get("System.State"),
                "assigned_to": fields.get("System.AssignedTo"),
            },
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
                "work-item-create.py currently supports only the REST backend"
            )

        patch_document = build_patch_document(args)
        requested_fields = build_requested_fields(args)
        encoded_type = quote(args.type, safe="")
        response = ado_rest_request(
            context,
            method="POST",
            path=f"_apis/wit/workitems/${encoded_type}",
            query={"fields": ",".join(RETURN_FIELDS)},
            body=patch_document,
            body_content_type="application/json-patch+json",
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            work_item_type=args.type,
            requested_fields=requested_fields,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
