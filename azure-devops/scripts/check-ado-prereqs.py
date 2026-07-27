#!/usr/bin/env python3
"""Check Azure DevOps script prerequisites."""

from __future__ import annotations

import argparse
import sys

from _ado_common import (
    AdoScriptError,
    add_common_arguments,
    classify_org_url,
    detect_cli,
    detect_extension,
    determine_backend_availability,
    emit_output,
    resolve_backend,
    resolve_context,
)



def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check Azure DevOps CLI and REST prerequisites")
    add_common_arguments(parser)
    return parser



def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    context = resolve_context(args)
    cli = detect_cli()
    extension = detect_extension()
    availability = determine_backend_availability(context)

    org_info = classify_org_url(context.get("org"))
    payload = {
        "ok": bool(availability["available"]),
        "context": {
            "org": context.get("org"),
            "project": context.get("project"),
            "deployment": org_info,
        },
        "cli": cli,
        "extension": extension,
        "auth": {
            "pat_present": bool(context.get("pat")),
        },
        "backend": {
            "requested": args.backend,
            "available": availability["available"],
            "preferred": availability["preferred"],
            "resolved": None,
        },
        "checks": {
            "org_present": bool(context.get("org")),
            "org_url_valid": org_info["valid"],
            "project_present": bool(context.get("project")),
            "pat_present": bool(context.get("pat")),
        },
    }

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
