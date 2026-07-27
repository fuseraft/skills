#!/usr/bin/env python3
"""List Azure DevOps pipeline runs via REST."""

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
    parser = argparse.ArgumentParser(description="List Azure DevOps pipeline runs")
    add_common_arguments(parser)
    parser.add_argument("--pipeline-id", type=int, help="Filter by pipeline ID")
    parser.add_argument("--branch", help="Filter by branch ref, for example refs/heads/main")
    parser.add_argument("--result", help="Filter by run result")
    parser.add_argument("--state", help="Filter by run state")
    parser.add_argument("--top", type=int, default=25, help="Maximum number of runs to return")
    parser.add_argument("--continuation-token", help="Continuation token from a previous response")
    return parser


def build_query(args: argparse.Namespace) -> Dict[str, Any]:
    query: Dict[str, Any] = {
        "$top": args.top,
        "branch": args.branch,
        "result": args.result,
        "state": args.state,
        "continuationToken": args.continuation_token,
    }
    if args.pipeline_id is not None:
        query["pipelineIds"] = args.pipeline_id
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
    runs = data.get("value", [])
    payload: Dict[str, Any] = {
        "operation": "pipeline-runs",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": query,
        "count": data.get("count", len(runs)),
        "runs": runs,
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
            raise AdoScriptError("pipeline-runs.py currently supports only the REST backend")

        query = build_query(args)
        response = ado_rest_request(
            context,
            method="GET",
            path="_apis/pipelines/runs",
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
