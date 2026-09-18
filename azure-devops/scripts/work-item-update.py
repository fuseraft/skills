#!/usr/bin/env python3
"""Update an Azure DevOps work item via REST."""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, List, Tuple

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
    "state": "System.State",
    "assigned_to": "System.AssignedTo",
    "description": "System.Description",
    "acceptance_criteria": "Microsoft.VSTS.Common.AcceptanceCriteria",
    "repro_steps": "Microsoft.VSTS.TCM.ReproSteps",
    "system_info": "Microsoft.VSTS.TCM.SystemInfo",
}

RETURN_FIELDS = [
    "System.WorkItemType",
    "System.Title",
    "System.State",
    "System.AssignedTo",
    "System.Description",
    "Microsoft.VSTS.Common.AcceptanceCriteria",
    "Microsoft.VSTS.TCM.ReproSteps",
    "Microsoft.VSTS.TCM.SystemInfo",
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Update an Azure DevOps work item")
    add_common_arguments(parser)
    parser.add_argument("--id", type=int, required=True, help="Work item ID")
    parser.add_argument("--title", help="Set System.Title")
    parser.add_argument("--state", help="Set System.State")
    parser.add_argument("--assigned-to", help="Set System.AssignedTo")
    parser.add_argument("--description", help="Set System.Description")
    parser.add_argument(
        "--acceptance-criteria",
        help="Set Microsoft.VSTS.Common.AcceptanceCriteria (commonly used on User Story/PBI items)",
    )
    parser.add_argument(
        "--repro-steps",
        help="Set Microsoft.VSTS.TCM.ReproSteps (commonly used on Bug items)",
    )
    parser.add_argument(
        "--system-info",
        help="Set Microsoft.VSTS.TCM.SystemInfo (commonly used on Bug items)",
    )
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
    operations: List[Dict[str, Any]] = []

    if args.title is not None:
        operations.append(
            {"op": "add", "path": "/fields/System.Title", "value": args.title}
        )
    if args.state is not None:
        operations.append(
            {"op": "add", "path": "/fields/System.State", "value": args.state}
        )
    if args.assigned_to is not None:
        operations.append(
            {
                "op": "add",
                "path": "/fields/System.AssignedTo",
                "value": args.assigned_to,
            }
        )
    if args.description is not None:
        operations.append(
            {
                "op": "add",
                "path": "/fields/System.Description",
                "value": args.description,
            }
        )
    if args.acceptance_criteria is not None:
        operations.append(
            {
                "op": "add",
                "path": f"/fields/{FIELD_ALIASES['acceptance_criteria']}",
                "value": args.acceptance_criteria,
            }
        )
    if args.repro_steps is not None:
        operations.append(
            {
                "op": "add",
                "path": f"/fields/{FIELD_ALIASES['repro_steps']}",
                "value": args.repro_steps,
            }
        )
    if args.system_info is not None:
        operations.append(
            {
                "op": "add",
                "path": f"/fields/{FIELD_ALIASES['system_info']}",
                "value": args.system_info,
            }
        )

    for raw_field in args.field:
        field_name, value = parse_field_assignment(raw_field)
        operations.append(
            {"op": "add", "path": f"/fields/{field_name}", "value": value}
        )

    if not operations:
        raise AdoScriptError(
            "Specify at least one update via --title, --state, --assigned-to, --description, "
            "--acceptance-criteria, --repro-steps, --system-info, or --field"
        )

    return operations


def build_requested_changes(args: argparse.Namespace) -> Dict[str, Any]:
    changes: Dict[str, Any] = {}
    if args.title is not None:
        changes[FIELD_ALIASES["title"]] = args.title
    if args.state is not None:
        changes[FIELD_ALIASES["state"]] = args.state
    if args.assigned_to is not None:
        changes[FIELD_ALIASES["assigned_to"]] = args.assigned_to
    if args.description is not None:
        changes[FIELD_ALIASES["description"]] = args.description
    if args.acceptance_criteria is not None:
        changes[FIELD_ALIASES["acceptance_criteria"]] = args.acceptance_criteria
    if args.repro_steps is not None:
        changes[FIELD_ALIASES["repro_steps"]] = args.repro_steps
    if args.system_info is not None:
        changes[FIELD_ALIASES["system_info"]] = args.system_info
    for raw_field in args.field:
        field_name, value = parse_field_assignment(raw_field)
        changes[field_name] = value
    return changes


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    requested_changes: Dict[str, Any],
    verbose: bool,
) -> Dict[str, Any]:
    work_item = response["data"] or {}
    fields = work_item.get("fields") or {}
    payload: Dict[str, Any] = {
        "operation": "work-item-update",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": {
            "id": work_item.get("id"),
            "changes": requested_changes,
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
                "work-item-update.py currently supports only the REST backend"
            )

        patch_document = build_patch_document(args)
        requested_changes = build_requested_changes(args)

        response = ado_rest_request(
            context,
            method="PATCH",
            path=f"_apis/wit/workitems/{args.id}",
            query={"fields": ",".join(RETURN_FIELDS)},
            body=patch_document,
            body_content_type="application/json-patch+json",
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            requested_changes=requested_changes,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
