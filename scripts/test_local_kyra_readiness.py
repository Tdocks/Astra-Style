#!/usr/bin/env python3
"""Focused tests for the local Edge Function worker readiness probe."""

import unittest
import pathlib
import sys
import io
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from run_local_kyra_acceptance import (
    HarnessError,
    classify_worker_probe,
    extract_acceptance_results,
    wait_function_worker,
)


class WorkerProbeClassificationTests(unittest.TestCase):
    def test_handler_validation_error_proves_worker_ready(self):
        body = b'{"error":{"category":"validation"},"request_id":"qa-request"}'

        self.assertEqual(classify_worker_probe(405, body), "ready")
        self.assertEqual(classify_worker_probe(404, body), "ready")

    def test_gateway_auth_error_does_not_prove_worker_ready(self):
        self.assertEqual(classify_worker_probe(404, b'{"message":"Invalid JWT"}'), "unexpected_response")

    def test_generic_upstream_gateway_responses_are_retryable(self):
        body = b"An invalid response was received from the upstream server"

        self.assertEqual(classify_worker_probe(502, body), "retry")
        self.assertEqual(classify_worker_probe(503, body), "retry")

    def test_worker_boot_error_is_immediate_even_with_gateway_status(self):
        self.assertEqual(classify_worker_probe(502, b"BOOT_ERROR: failed to determine entrypoint"), "boot_error")

    def test_unrelated_server_errors_are_not_retried(self):
        self.assertEqual(classify_worker_probe(502, b"database unavailable"), "http_error")
        self.assertEqual(classify_worker_probe(500, b"upstream server"), "http_error")

    def test_generic_gateway_replies_retry_until_handler_is_ready(self):
        def response(code, body):
            return urllib.error.HTTPError("http://localhost/functions/v1/kyra/respond", code, "", {}, io.BytesIO(body))

        with (
            patch("run_local_kyra_acceptance.time.monotonic", side_effect=[0, 0, 1, 2]),
            patch("run_local_kyra_acceptance.time.sleep") as sleep,
            patch(
                "run_local_kyra_acceptance.urllib.request.urlopen",
                side_effect=[
                    response(502, b"invalid response from upstream server"),
                    response(503, b"invalid response from upstream server"),
                    response(405, b'{"error":{"category":"validation"},"request_id":"ready"}'),
                ],
            ),
        ):
            self.assertEqual(wait_function_worker("http://127.0.0.1:54321", "local", timeout=10), 405)

        self.assertEqual(sleep.call_count, 2)

    def test_persistent_generic_gateway_reply_stops_at_deadline(self):
        upstream = urllib.error.HTTPError(
            "http://localhost/functions/v1/kyra/respond",
            502,
            "",
            {},
            io.BytesIO(b"invalid response from upstream server"),
        )
        with (
            patch("run_local_kyra_acceptance.time.monotonic", side_effect=[0, 0, 1]),
            patch("run_local_kyra_acceptance.time.sleep"),
            patch("run_local_kyra_acceptance.urllib.request.urlopen", side_effect=[upstream]),
        ):
            with self.assertRaisesRegex(HarnessError, "last HTTP status 502") as raised:
                wait_function_worker("http://127.0.0.1:54321", "local", timeout=0.5)

        self.assertEqual(raised.exception.worker_status, 502)


class AcceptanceResultExtractionTests(unittest.TestCase):
    def test_current_xcresult_suite_names_are_recognized(self):
        report = {
            "testNodes": [
                {
                    "name": "Analytics event privacy contract",
                    "children": [
                        {"name": "Every spec event has a fixed name", "result": "Passed"},
                        {"name": "Feedback inputs are allowlisted", "result": "Passed"},
                    ],
                },
                {
                    "name": "testAskKyraRendersOnlyFixtureOwnersClosetItems()",
                    "result": "Passed",
                },
            ]
        }

        ui_results, privacy_results = extract_acceptance_results(
            report, "testAskKyraRendersOnlyFixtureOwnersClosetItems"
        )

        self.assertEqual(ui_results, ["Passed"])
        self.assertEqual(privacy_results, ["Passed", "Passed"])

    def test_missing_or_skipped_privacy_cases_fail_closed(self):
        report = {
            "testNodes": [
                {"name": "Analytics event privacy contract", "children": []},
                {
                    "name": "testAskKyraRendersOnlyFixtureOwnersClosetItems()",
                    "result": "Passed",
                },
            ]
        }

        ui_results, privacy_results = extract_acceptance_results(
            report, "testAskKyraRendersOnlyFixtureOwnersClosetItems"
        )

        self.assertEqual(ui_results, ["Passed"])
        self.assertEqual(privacy_results, [])


if __name__ == "__main__":
    unittest.main()
