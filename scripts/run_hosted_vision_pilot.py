#!/usr/bin/env python3
"""Bounded real scanner benchmark; credentials/session never enter reports or logs."""
import argparse
import hashlib
import json
import math
import pathlib
import secrets
import time
import urllib.error
import urllib.request
import uuid


def request(url, headers, body=None, method="GET", raw=False):
    data = body if raw else None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=65)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        content = response.read(2_000_000)
        return response.code, json.loads(content) if content else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repetitions", type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.repetitions <= 3:
        raise ValueError("Use one to three repetitions for this bounded run.")
    manifest = pathlib.Path(args.manifest)
    items = json.loads(manifest.read_text())["items"]
    if not 1 <= len(items) <= 20:
        raise ValueError("Use one to twenty independently labeled images.")
    for item in items:
        if hashlib.sha256((manifest.parent / item["image"]).read_bytes()).hexdigest() != item["sha256"]:
            raise ValueError("Image does not match its frozen manifest.")
    keys = json.loads(pathlib.Path(args.credentials).read_text())
    admin = next(x["api_key"] for x in keys if x.get("name") == "service_role")
    anon = next(x["api_key"] for x in keys if x.get("name") == "anon")
    base = "https://anutsdzbxycaavmmkewo.supabase.co"
    admin_headers = {"apikey": admin, "Authorization": "Bearer " + admin,
                     "Content-Type": "application/json"}
    anon_headers = {"apikey": anon, "Content-Type": "application/json"}
    password = secrets.token_urlsafe(40)
    email = "scanner-pilot-" + uuid.uuid4().hex + "@example.invalid"
    uid = None
    paths = []
    observations = []
    cleanup = {"storage_empty": False, "user_deleted": False}
    run_error = None
    try:
        status, user = request(base + "/auth/v1/admin/users", admin_headers,
                               {"email": email, "password": password, "email_confirm": True}, "POST")
        if status != 200:
            raise RuntimeError("Could not create disposable scanner fixture.")
        uid = user["id"]
        status, session = request(base + "/auth/v1/token?grant_type=password", anon_headers,
                                  {"email": email, "password": password}, "POST")
        if status != 200:
            raise RuntimeError("Could not authenticate disposable scanner fixture.")
        headers = {**anon_headers, "Authorization": "Bearer " + session["access_token"]}
        for item in items:
            path = f"users/{uid}/captures/{uuid.uuid4()}.jpg"
            status, _ = request(base + "/storage/v1/object/user-content/" + path,
                                {**headers, "Content-Type": "image/jpeg"},
                                (manifest.parent / item["image"]).read_bytes(), "POST", True)
            if status not in (200, 201):
                raise RuntimeError(f"Upload failed for image {item['id']} (HTTP {status}).")
            paths.append(path)
            for repetition in range(1, args.repetitions + 1):
                request_id = str(uuid.uuid4())
                started = time.monotonic()
                status, envelope = request(base + "/functions/v1/closet/analyze-item",
                    {**headers, "Idempotency-Key": str(uuid.uuid4())},
                    {"body": {"request_id": request_id, "storage_path": path, "image_type": "front"}}, "POST")
                if status != 200 or not isinstance(envelope.get("data"), dict):
                    raise RuntimeError(f"Analysis failed for image {item['id']} (HTTP {status}).")
                result = envelope["data"]
                value = lambda name: result.get(name, {}).get("value")
                values = {name: value(name) for name in ["category", "subcategory", "primary_color", "pattern", "formality_score"]}
                subtype = str(values["subcategory"] or "").lower()
                color = str(values["primary_color"] or "").lower().split()
                scores = {
                    "category": values["category"] == item["category"],
                    "subcategory": any(all(word in subtype for word in group) for group in item["subcategoryAlternatives"]),
                    "primaryColor": bool(color) and color[-1] in item["primaryColor"],
                    "pattern": values["pattern"] in item["pattern"],
                    "formality": isinstance(values["formality_score"], (int, float)) and abs(values["formality_score"] - item["formality"]) <= 15,
                }
                observation = {"image_id": item["id"], "repetition": repetition,
                               "elapsed_ms": round((time.monotonic() - started) * 1000),
                               "scores": scores, "values": values,
                               "category_confidence": result.get("category", {}).get("confidence"),
                               "low_confidence_fields": result.get("fields_below_confidence_threshold", [])}
                observations.append(observation)
                pathlib.Path(args.output).write_text(json.dumps({"observations": observations, "complete": False}, indent=2))
                print(f"Image {item['id']:02d}, run {repetition}: {observation['elapsed_ms']} ms, {sum(scores.values())}/5 fields", flush=True)
    except Exception as error:
        run_error = str(error)
    finally:
        if uid:
            # Delete only objects and the account created by this invocation.
            if paths:
                status, _ = request(base + "/storage/v1/object/user-content", admin_headers,
                                    {"prefixes": paths}, "DELETE")
                if status != 200:
                    run_error = run_error or "Fixture image cleanup failed."
            status, listing = request(base + "/storage/v1/object/list/user-content", admin_headers,
                                      {"prefix": f"users/{uid}/", "limit": 100}, "POST")
            cleanup["storage_empty"] = status == 200 and listing == []
            status, _ = request(base + "/auth/v1/admin/users/" + uid, admin_headers, method="DELETE")
            status, _ = request(base + "/auth/v1/admin/users/" + uid, admin_headers)
            cleanup["user_deleted"] = status == 404
    bars = {"category": .98, "subcategory": .80, "primaryColor": .90, "pattern": .85, "formality": .85}
    accuracy = {field: sum(o["scores"][field] for o in observations) / len(observations)
                for field in bars} if observations else {}
    elapsed = sorted(o["elapsed_ms"] for o in observations)
    percentiles = {f"p{p}": elapsed[math.ceil(len(elapsed) * p / 100) - 1]
                   for p in (50, 95)} if elapsed else {}
    disagreement = {}
    for field, wire in [("category", "category"), ("subcategory", "subcategory"),
                        ("primaryColor", "primary_color"), ("pattern", "pattern")]:
        groups = [[o["values"][wire] for o in observations if o["image_id"] == item["id"]] for item in items]
        disagreement[field] = sum(len(set(group)) > 1 for group in groups) / len(items)
    complete = len(observations) == len(items) * args.repetitions and run_error is None
    criterion_disagreement = {
        field: sum(len({o["scores"][field] for o in observations if o["image_id"] == item["id"]}) > 1
                   for item in items) / len(items)
        for field in bars
    }
    gate_passed = (complete and all(cleanup.values())
                   and all(accuracy.get(field, 0) >= bar for field, bar in bars.items())
                   and percentiles.get("p50", float("inf")) <= 5500
                   and all(rate <= .15 for rate in criterion_disagreement.values()))
    report = {"complete": complete, "photos": len(items), "repetitions": args.repetitions,
              "provider_errors": run_error, "accuracy": accuracy, "bars": bars,
              "latency_ms": percentiles, "raw_value_disagreement": disagreement,
              "criterion_disagreement": criterion_disagreement, "gate_passed": gate_passed,
              "cleanup": cleanup, "observations": observations}
    pathlib.Path(args.output).write_text(json.dumps(report, indent=2))
    print(json.dumps({k: v for k, v in report.items() if k != "observations"}, indent=2))
    return 2 if not complete or not all(cleanup.values()) else 0 if gate_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
