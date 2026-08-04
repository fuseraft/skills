#!/usr/bin/env python3
"""Add a comment thread to an Azure DevOps pull request via REST."""

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

THREAD_STATUSES = ("active", "closed", "fixed", "wontFix", "byDesign", "pending")
COMMENT_TYPES = ("text", "codeChange")
DEFAULT_THREAD_CONTEXT_FILE_PATH = "/"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Add a comment thread to an Azure DevOps pull request"
    )
    add_common_arguments(parser, include_repo=True)
    parser.add_argument("--id", required=True, type=int, help="Pull request ID")
    parser.add_argument("--comment", required=True, help="Comment text to add")
    parser.add_argument(
        "--status",
        choices=THREAD_STATUSES,
        default="active",
        help="Initial thread status",
    )
    parser.add_argument(
        "--comment-type",
        choices=COMMENT_TYPES,
        default="text",
        help="Comment type to send to Azure DevOps",
    )
    parser.add_argument(
        "--file-path",
        help="Optional repo-relative file path for a file-scoped thread",
    )
    parser.add_argument(
        "--right-file-start-line",
        type=int,
        help="Optional 1-based start line for the right file context",
    )
    parser.add_argument(
        "--right-file-start-offset",
        type=int,
        default=1,
        help="1-based start column for the right file context (default: 1)",
    )
    parser.add_argument(
        "--right-file-end-line",
        type=int,
        help="Optional 1-based end line for the right file context",
    )
    parser.add_argument(
        "--right-file-end-offset",
        type=int,
        default=1,
        help="1-based end column for the right file context (default: 1)",
    )
    return parser


def build_pr_threads_path(repo: str, pr_id: int) -> str:
    encoded_repo = quote(repo, safe="")
    return f"_apis/git/repositories/{encoded_repo}/pullRequests/{pr_id}/threads"


def validate_context_arguments(args: argparse.Namespace) -> None:
    line_args = [
        args.right_file_start_line,
        args.right_file_end_line,
    ]
    has_line_context = any(value is not None for value in line_args)

    if has_line_context and not args.file_path:
        raise AdoScriptError(
            "--file-path is required when specifying line-based thread context"
        )

    if args.file_path and args.right_file_start_line is None and args.right_file_end_line is None:
        return

    if args.right_file_start_line is None or args.right_file_end_line is None:
        raise AdoScriptError(
            "Both --right-file-start-line and --right-file-end-line are required together"
        )

    if args.right_file_start_line < 1 or args.right_file_end_line < 1:
        raise AdoScriptError("Line numbers must be 1 or greater")
    if args.right_file_start_offset < 1 or args.right_file_end_offset < 1:
        raise AdoScriptError("Column offsets must be 1 or greater")
    if args.right_file_end_line < args.right_file_start_line:
        raise AdoScriptError("End line cannot be less than start line")
    if (
        args.right_file_end_line == args.right_file_start_line
        and args.right_file_end_offset < args.right_file_start_offset
    ):
        raise AdoScriptError(
            "End column cannot be less than start column on the same line"
        )


def build_thread_context(args: argparse.Namespace) -> Optional[Dict[str, Any]]:
    if not args.file_path:
        return None
    if args.right_file_start_line is None and args.right_file_end_line is None:
        return {
            "filePath": args.file_path,
        }
    return {
        "filePath": args.file_path,
        "rightFileStart": {
            "line": args.right_file_start_line,
            "offset": args.right_file_start_offset,
        },
        "rightFileEnd": {
            "line": args.right_file_end_line,
            "offset": args.right_file_end_offset,
        },
    }


def build_request_body(args: argparse.Namespace) -> Dict[str, Any]:
    body: Dict[str, Any] = {
        "status": args.status,
        "comments": [
            {
                "parentCommentId": 0,
                "content": args.comment,
                "commentType": args.comment_type,
            }
        ],
    }
    thread_context = build_thread_context(args)
    if thread_context is not None:
        body["threadContext"] = thread_context
    return body


def build_payload(
    *,
    context: Dict[str, str | None],
    backend: str,
    response: Dict[str, Any],
    repo: str,
    pr_id: int,
    request_body: Dict[str, Any],
    verbose: bool,
) -> Dict[str, Any]:
    thread = response["data"] or {}
    payload: Dict[str, Any] = {
        "operation": "pr-comment",
        "backend": backend,
        "context": build_context_payload(
            context,
            availability=determine_backend_availability(context),
            requested_backend=backend,
            include_repo=True,
            verbose=verbose,
        ),
        "request": {
            "repo": repo,
            "id": pr_id,
            "thread": request_body,
        },
        "thread": thread,
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
        validate_context_arguments(args)
        context = resolve_context(args, include_repo=True)
        repo = require_context_value(context, "repo", "repository name")
        availability = determine_backend_availability(context)
        backend = resolve_backend(args.backend, availability)
        if backend != "rest":
            raise AdoScriptError(
                "pr-comment.py currently supports only the REST backend"
            )

        request_body = build_request_body(args)
        response = ado_rest_request(
            context,
            method="POST",
            path=build_pr_threads_path(repo, args.id),
            project=context.get("project"),
            body=request_body,
        )

        payload = build_payload(
            context=context,
            backend=backend,
            response=response,
            repo=repo,
            pr_id=args.id,
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
