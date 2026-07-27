#!/usr/bin/env python3
"""Show resolved Azure DevOps context for other skill scripts."""

from __future__ import annotations

import argparse
import sys

from _ado_common import (
    AdoScriptError,
    add_common_arguments,
    build_context_payload,
    determine_backend_availability,
    emit_output,
    resolve_backend,
    resolve_context,
)



def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Show resolved Azure DevOps context")
    add_common_arguments(parser, include_repo=True)
    return parser



def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    context = resolve_context(args, include_repo=True)
    availability = determine_backend_availability(context)

    payload = build_context_payload(
        context,
        availability=availability,
        requested_backend=args.backend,
        include_repo=True,
        verbose=args.verbose,
    )

    try:
        payload["backend"]["resolved"] = resolve_backend(args.backend, availability)
    except AdoScriptError as exc:
        payload["error"] = str(exc)
        emit_output(payload, args.output)
        return 1

    emit_output(payload, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
