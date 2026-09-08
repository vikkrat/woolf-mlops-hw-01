"""Lambda #2: emits a structured completion audit event."""

import json


def lambda_handler(event: dict, _context: object) -> dict:
    result = {
        "pipeline_status": "SUCCEEDED",
        "git_sha": event.get("git_sha"),
        "training_job": "completed",
    }
    print(json.dumps({"event_type": "training_audit", **result}))
    return result
