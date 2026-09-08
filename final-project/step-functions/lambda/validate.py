"""Lambda #1: validates the request before an expensive EKS training job."""

from __future__ import annotations

import re

SHA_PATTERN = re.compile(r"^[0-9a-f]{7,40}$")


def lambda_handler(event: dict, _context: object) -> dict:
    git_sha = str(event.get("git_sha", ""))
    if not SHA_PATTERN.fullmatch(git_sha):
        raise ValueError("git_sha must contain 7-40 lowercase hexadecimal characters")
    return {
        "validated": True,
        "git_sha": git_sha,
        "source": str(event.get("source", "unknown"))[:64],
    }
