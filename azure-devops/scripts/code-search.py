#!/usr/bin/env python3
"""Search code across Azure DevOps Git repositories via the Search REST API.

Requires the Code Search extension/feature to be enabled for the
organization or collection. On Azure DevOps Services (cloud) the search
API is hosted on a dedicated ``almsearch.dev.azure.com`` host; on Azure
DevOps Server / on-prem collections it is exposed on the same collection
URL used for every other REST call in this skill.
"""

from __future__ import annotations

import argparse
import sys
from typing import Any, Dict, List, Optional

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
    resolve_search_base_url,
)

SEARCH_API_VERSION = "7.1-preview.1"
DEFAULT_TOP = 25


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Search code across Azure DevOps Git repositories"
    )
    add_common_arguments(parser)
    parser.add_argument("--text", required=True, help="Search text or query, e.g. ext:cs myFunction")
    parser.add_argument(
        "--repo",
        action="append",
        default=[],
        metavar="NAME",
        help="Limit results to a repository name; repeatable",
    )
    parser.add_argument(
        "--path",
        action="append",
        default=[],
        metavar="PATH",
        help="Limit results to a repository-relative path prefix; repeatable",
    )
    parser.add_argument(
        "--branch",
        action="append",
        default=[],
        metavar="NAME",
        help="Limit results to a branch name; repeatable",
    )
    parser.add_argument(
        "--extension",
        action="append",
        default=[],
        metavar="EXT",
        help="Limit results to a file extension, e.g. cs, py; repeatable",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=DEFAULT_TOP,
        help=f"Maximum number of results to return (default: {DEFAULT_TOP})",
    )
    parser.add_argument("--skip", type=int, default=0, help="Number of results to skip")
    parser.add_argument(
        "--include-facets",
        action="store_true",
        help="Include facet counts (repository, project, path, etc.) in the response",
    )
    return parser


def build_filters(args: argparse.Namespace, project: str) -> Dict[str, List[str]]:
    filters: Dict[str, List[str]] = {"Project": [project]}
    if args.repo:
        filters["Repository"] = args.repo
    if args.path:
        filters["Path"] = args.path
    if args.branch:
        filters["Branch"] = args.branch
    if args.extension:
        filters["CodeElement"] = args.extension
    return filters


def build_request_body(args: argparse.Namespace, project: str) -> Dict[str, Any]:
    body: Dict[str, Any] = {
        "searchText": args.text,
        "$skip": args.skip,
        "$top": args.top,
        "filters": build_filters(args, project),
        "includeFacets": args.include_facets,
    }
    return body


def summarize_results(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    results = data.get("results") or []
    summaries: List[Dict[str, Any]] = []
    for item in results:
        summaries.append(
            {
                "fileName": item.get("fileName"),
                "path": item.get("path"),
                "repository": (item.get("repository") or {}).get("name"),
                "project": (item.get("project") or {}).get("name"),
                "branch": (item.get("versions") or [{}])[0].get("branchName")
                if item.get("versions")
                else None,
                "contentId": item.get("contentId"),
            }
        )
    return summaries


def build_payload(
    *,
    context: Dict[str, Optional[str]],
    backend: str,
    response: Dict[str, Any],
    request_body: Dict[str, Any],
    verbose: bool,
) -> Dict[str, Any]:
    data = response["data"] or {}
    payload: Dict[str, Any] = {
        "operation": "code-search",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            verbose=verbose,
        ),
        "request": request_body,
        "count": data.get("count", len(data.get("results") or [])),
        "results": summarize_results(data),
    }
    if data.get("facets"):
        payload["facets"] = data["facets"]
    if verbose:
        payload["rest"] = {
            "status_code": response["status_code"],
            "url": response["url"],
        }
        payload["raw"] = data
    return payload


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    context = resolve_context(args)

    try:
        project = require_context_value(context, "project", "project name")
        availability = determine_backend_availability(context)
        backend = resolve_backend(args.backend, availability)
        if backend != "rest":
            raise AdoScriptError("code-search.py currently supports only the REST backend")

        request_body = build_request_body(args, project)
        search_base_url = resolve_search_base_url(context.get("org"))

        try:
            response = ado_rest_request(
                context,
                method="POST",
                path="_apis/search/codesearchresults",
                project=project,
                body=request_body,
                api_version=SEARCH_API_VERSION,
                base_url_override=search_base_url,
            )
        except AdoScriptError as exc:
            message = str(exc)
            if "TF400813" in message or "404" in message or "not found" in message.lower():
                raise AdoScriptError(
                    "Code search is unavailable. Confirm the Code Search "
                    "extension/feature is installed and enabled for this "
                    f"organization or collection. Original error: {message}"
                ) from exc
            raise

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            request_body=request_body,
            verbose=args.verbose,
        )
        emit_output(payload, args.output)
        return 0
    except AdoScriptError as exc:
        emit_output({"error": str(exc)}, args.output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
