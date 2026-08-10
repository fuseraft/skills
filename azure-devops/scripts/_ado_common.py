#!/usr/bin/env python3
"""Shared helpers for Azure DevOps skill scripts."""

from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import Request, urlopen
from typing import Any, Dict, Optional


DEFAULT_ENV = {
    "org": "ADO_URL",
    "project": "ADO_PROJECT",
    "pat": "ADO_PAT",
    "repo": "ADO_REPO",
}

DEFAULT_API_VERSION = "7.0"


def _load_dotenv_if_present() -> None:
    current = Path(__file__).resolve().parent
    candidates = [current.parent / ".env", Path.cwd() / ".env"]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        for raw_line in candidate.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if key and key not in os.environ:
                os.environ[key] = value.strip()
        break


_load_dotenv_if_present()


KNOWN_CLOUD_HOSTS = {
    "dev.azure.com",
    "visualstudio.com",
}


class AdoScriptError(Exception):
    """Raised for expected script-level failures."""



def add_common_arguments(parser: argparse.ArgumentParser, *, include_repo: bool = False) -> None:
    parser.add_argument("--org", help="Azure DevOps organization or collection URL")
    parser.add_argument("--project", help="Azure DevOps project name")
    if include_repo:
        parser.add_argument("--repo", help="Azure DevOps repository name")
    parser.add_argument(
        "--backend",
        choices=("auto", "cli", "rest"),
        default="auto",
        help="Backend selection mode",
    )
    parser.add_argument(
        "--output",
        choices=("json", "table", "tsv"),
        default="json",
        help="Output format",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Include additional diagnostic detail in output",
    )



def normalize_org_url(org: Optional[str]) -> Optional[str]:
    if not org:
        return None
    return org.strip().rstrip("/")



def classify_org_url(org: Optional[str]) -> Dict[str, Any]:
    normalized = normalize_org_url(org)
    if not normalized:
        return {
            "provided": False,
            "normalized": None,
            "host": None,
            "scheme": None,
            "path": None,
            "deployment": "unknown",
            "cloud_host": False,
            "on_prem": False,
            "valid": False,
            "reason": "No Azure DevOps organization or collection URL provided",
        }

    parsed = urlparse(normalized)
    host = parsed.netloc.lower()
    scheme = parsed.scheme.lower()
    path = parsed.path or "/"
    is_valid = bool(host) and scheme in {"http", "https"}
    cloud_host = host.endswith("dev.azure.com") or host.endswith("visualstudio.com")
    on_prem = is_valid and not cloud_host
    deployment = "cloud" if cloud_host else ("server" if on_prem else "unknown")
    reason = None if is_valid else "Organization URL must include http:// or https:// and a host name"

    return {
        "provided": True,
        "normalized": normalized,
        "host": host or None,
        "scheme": scheme or None,
        "path": path,
        "deployment": deployment,
        "cloud_host": cloud_host,
        "on_prem": on_prem,
        "valid": is_valid,
        "reason": reason,
    }



def resolve_context(args: argparse.Namespace, *, include_repo: bool = False) -> Dict[str, Optional[str]]:
    org = normalize_org_url(args.org or os.getenv(DEFAULT_ENV["org"]))
    context: Dict[str, Optional[str]] = {
        "org": org,
        "project": args.project or os.getenv(DEFAULT_ENV["project"]),
        "pat": os.getenv(DEFAULT_ENV["pat"]),
    }
    if include_repo:
        context["repo"] = getattr(args, "repo", None) or os.getenv(DEFAULT_ENV["repo"])
    return context



def detect_cli() -> Dict[str, Any]:
    az_path = shutil.which("az")
    return {
        "installed": bool(az_path),
        "path": az_path,
    }



def detect_extension() -> Dict[str, Any]:
    # Conservative detection: only report availability if the CLI exists.
    cli = detect_cli()
    return {
        "installed": False if not cli["installed"] else None,
        "detail": "Azure CLI not found; Azure DevOps extension status unknown" if not cli["installed"] else "Unverified without invoking az extension list",
    }



def detect_auth(context: Dict[str, Optional[str]]) -> Dict[str, Any]:
    pat = context.get("pat")
    return {
        "pat_present": bool(pat),
        "pat_source": DEFAULT_ENV["pat"] if pat else None,
    }



def determine_backend_availability(context: Dict[str, Optional[str]]) -> Dict[str, Any]:
    cli = detect_cli()
    auth = detect_auth(context)
    org_info = classify_org_url(context.get("org"))
    cli_mode = cli["installed"]
    rest_mode = auth["pat_present"] and org_info["valid"] and bool(context.get("project"))
    available = []
    if cli_mode:
        available.append("cli")
    if rest_mode:
        available.append("rest")
    return {
        "cli": cli_mode,
        "rest": rest_mode,
        "available": available,
        "preferred": "cli" if cli_mode else ("rest" if rest_mode else None),
        "org": org_info,
    }



def resolve_backend(requested: str, availability: Dict[str, Any]) -> str:
    if requested == "auto":
        preferred = availability.get("preferred")
        if not preferred:
            raise AdoScriptError("No usable Azure DevOps backend is available")
        return preferred
    if not availability.get(requested):
        raise AdoScriptError(f"Requested backend '{requested}' is not available")
    return requested



def emit_output(payload: Dict[str, Any], output_format: str) -> None:
    if output_format == "json":
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return

    rows = flatten_for_table(payload)
    if output_format == "tsv":
        for key, value in rows:
            sys.stdout.write(f"{key}\t{value}\n")
        return

    key_width = max((len(key) for key, _ in rows), default=3)
    for key, value in rows:
        sys.stdout.write(f"{key.ljust(key_width)} : {value}\n")



def flatten_for_table(payload: Dict[str, Any], prefix: str = "") -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for key, value in payload.items():
        full_key = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            rows.extend(flatten_for_table(value, full_key))
        elif isinstance(value, list):
            rows.append((full_key, json.dumps(value)))
        else:
            rows.append((full_key, "" if value is None else str(value)))
    return rows



def mask_secret(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    if len(value) <= 4:
        return "*" * len(value)
    return f"{value[:2]}***{value[-2:]}"



def build_context_payload(
    context: Dict[str, Optional[str]],
    *,
    availability: Dict[str, Any],
    requested_backend: str,
    include_repo: bool = False,
    verbose: bool = False,
) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "org": context.get("org"),
        "project": context.get("project"),
        "deployment": availability.get("org", {}),
        "backend": {
            "requested": requested_backend,
            "available": availability["available"],
            "preferred": availability["preferred"],
        },
        "auth": {
            "pat_present": bool(context.get("pat")),
        },
    }
    if include_repo:
        payload["repo"] = context.get("repo")
    if verbose:
        payload["auth"]["pat_preview"] = mask_secret(context.get("pat"))
        payload["cli"] = detect_cli()
        payload["extension"] = detect_extension()
    return payload


def require_context_value(context: Dict[str, Optional[str]], key: str, description: str) -> str:
    value = context.get(key)
    if not value:
        raise AdoScriptError(f"Missing required {description}")
    return value


def get_basic_auth_header(pat: str) -> str:
    token = f":{pat}".encode("utf-8")
    return "Basic " + base64.b64encode(token).decode("ascii")


def resolve_search_base_url(org: str) -> str:
    """Resolve the base URL to use for Azure DevOps Search API calls.

    Azure DevOps Services (cloud) hosts the Search/Code Search API on a
    dedicated ``almsearch.dev.azure.com`` host, with the organization name
    kept in the path (e.g. ``https://dev.azure.com/my-org`` becomes
    ``https://almsearch.dev.azure.com/my-org``).

    Azure DevOps Server / on-prem collections do not use a separate search
    host; the Search REST API (when the Code Search extension is installed)
    is exposed on the same collection URL used for every other REST call.
    """
    normalized = normalize_org_url(org) or ""
    org_info = classify_org_url(normalized)
    if not org_info["valid"]:
        return normalized

    if org_info["cloud_host"]:
        parsed = urlparse(normalized)
        if parsed.netloc.lower().endswith("visualstudio.com"):
            # https://{org}.visualstudio.com -> https://almsearch.dev.azure.com/{org}
            org_name = parsed.netloc.split(".")[0]
            path = f"/{org_name}{parsed.path}" if parsed.path else f"/{org_name}"
        else:
            # https://dev.azure.com/{org} -> https://almsearch.dev.azure.com/{org}
            path = parsed.path
        return f"{parsed.scheme}://almsearch.dev.azure.com{path}".rstrip("/")

    return normalized


def build_rest_url(
    org: str,
    path: str,
    *,
    project: Optional[str] = None,
    query: Optional[Dict[str, Any]] = None,
    api_version: str = DEFAULT_API_VERSION,
) -> str:
    base = org.rstrip("/")
    relative = path.lstrip("/")
    if project:
        relative = f"{quote(project, safe='')}/{relative}"
    query_params: Dict[str, Any] = {"api-version": api_version}
    if query:
        for key, value in query.items():
            if value is not None:
                query_params[key] = value
    return f"{base}/{relative}?{urlencode(query_params, doseq=True)}"


def ado_rest_request(
    context: Dict[str, Optional[str]],
    *,
    method: str,
    path: str,
    project: Optional[str] = None,
    query: Optional[Dict[str, Any]] = None,
    body: Optional[Any] = None,
    body_content_type: str = "application/json",
    headers: Optional[Dict[str, str]] = None,
    api_version: str = DEFAULT_API_VERSION,
    accept: str = "application/json",
    base_url_override: Optional[str] = None,
) -> Dict[str, Any]:
    org = base_url_override or require_context_value(context, "org", "organization or collection URL")
    pat = require_context_value(context, "pat", "personal access token")
    url = build_rest_url(org, path, project=project, query=query, api_version=api_version)

    request_headers = {
        "Authorization": get_basic_auth_header(pat),
        "Accept": accept,
    }
    if headers:
        request_headers.update(headers)

    data: Optional[bytes] = None
    if body is not None:
        request_headers.setdefault("Content-Type", body_content_type)
        if isinstance(body, bytes):
            data = body
        else:
            data = json.dumps(body).encode("utf-8")

    request = Request(url=url, data=data, method=method.upper(), headers=request_headers)

    try:
        with urlopen(request) as response:
            raw = response.read().decode("utf-8")
            parsed = json.loads(raw) if raw else None
            return {
                "status_code": response.getcode(),
                "url": url,
                "data": parsed,
            }
    except HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        details: Any
        try:
            details = json.loads(error_body) if error_body else None
        except json.JSONDecodeError:
            details = error_body or None
        raise AdoScriptError(
            f"Azure DevOps REST request failed with status {exc.code}: {details}"
        ) from exc
    except URLError as exc:
        raise AdoScriptError(f"Azure DevOps REST request failed: {exc.reason}") from exc
