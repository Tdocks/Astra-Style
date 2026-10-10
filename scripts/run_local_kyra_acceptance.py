#!/usr/bin/env python3
"""Run the real Kyra UI flow against an isolated local Supabase stack.

The only external behavior is a deterministic local provider stub. Supabase
credentials and the short-lived fixture session stay in owner-only temporary
files and are never printed or passed on a process command line.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import datetime


ROOT = pathlib.Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
FIXTURE = IOS / ".local-qa" / "kyra-fixture.json"
CLI_VERSION = "2.120.0"
EXCLUDED = (
    "realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,logflare,"
    "vector,supavisor"
)


class HarnessError(RuntimeError):
    pass


def run(args: list[str], *, cwd: pathlib.Path = ROOT, env=None, timeout=300,
        check=True, capture=True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        timeout=timeout,
        check=False,
    )
    if check and result.returncode:
        # Supabase start can print its local keys. Never echo tool output here.
        raise HarnessError(f"Local QA command failed ({pathlib.Path(args[0]).name}, exit {result.returncode}).")
    return result


def request_json(url: str, *, method="GET", headers=None, body=None, timeout=15):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(2_000_001)
            if len(raw) > 2_000_000:
                raise HarnessError("Local QA endpoint returned an oversized response.")
            try:
                payload = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                payload = None
            return response.status, payload
    except urllib.error.HTTPError as error:
        raw = error.read(32_768)
        try:
            payload = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            payload = None
        return error.code, payload


def wait_http(url: str, *, timeout=120, expected=200):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            status, _ = request_json(url, timeout=2)
            if status == expected:
                return
        except (OSError, ValueError, urllib.error.URLError):
            pass
        time.sleep(1)
    raise HarnessError("A required local QA service did not become ready in time.")


def wait_function_worker(api_url: str, anon_key: str, *, timeout=90):
    """Wait for the actual Kyra worker, not just the Functions gateway."""
    url = api_url.rstrip("/") + "/functions/v1/kyra/respond"
    headers = {"apikey": anon_key, "Authorization": f"Bearer {anon_key}"}
    deadline = time.monotonic() + timeout
    last_status = None
    while time.monotonic() < deadline:
        request = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                last_status = response.status
                body = response.read(16_384)
        except urllib.error.HTTPError as error:
            last_status = error.code
            body = error.read(16_384)
        except (OSError, urllib.error.URLError):
            time.sleep(1)
            continue

        # A route-level method/not-found response proves the worker booted.
        # Gateway auth failures and BOOT_ERROR responses do not.
        body_text = body.decode("utf-8", errors="replace")
        if "BOOT_ERROR" in body_text or "failed to determine entrypoint" in body_text.lower():
            raise HarnessError("The local Kyra Edge Function worker failed to boot.")
        try:
            envelope = json.loads(body_text)
        except json.JSONDecodeError:
            envelope = None
        if (last_status in (404, 405) and isinstance(envelope, dict)
                and isinstance(envelope.get("error"), dict)
                and envelope["error"].get("category") == "validation"
                and isinstance(envelope.get("request_id"), str)):
            return
        if last_status >= 500:
            raise HarnessError(f"The local Kyra Edge Function worker returned HTTP {last_status} during startup.")
        time.sleep(1)
    raise HarnessError(
        f"The local Kyra Edge Function worker did not become ready (last HTTP status {last_status})."
    )


def parse_local_status(workdir: pathlib.Path) -> dict[str, str]:
    result = run(
        ["npx", "--yes", f"supabase@{CLI_VERSION}", "status", "--output", "json", "--workdir", str(workdir)],
        timeout=60,
    )
    try:
        values = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise HarnessError("Could not parse local Supabase status.") from error
    aliases = {
        "API_URL": ("API_URL", "api_url"),
        "ANON_KEY": ("ANON_KEY", "anon_key"),
        "SERVICE_ROLE_KEY": ("SERVICE_ROLE_KEY", "service_role_key"),
    }
    parsed = {}
    for destination, names in aliases.items():
        value = next((values.get(name) for name in names if values.get(name)), None)
        if not isinstance(value, str) or not value:
            raise HarnessError("Local Supabase status omitted a required local endpoint value.")
        parsed[destination] = value
    api = urllib.parse.urlparse(parsed["API_URL"])
    if api.scheme != "http" or api.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise HarnessError("Refusing to continue: Supabase endpoint is not loopback HTTP.")
    return parsed


def write_private(path: pathlib.Path, payload: bytes):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    os.chmod(path, 0o600)


def wait_for_port(host: str, port: int, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=1):
                return
        except OSError:
            time.sleep(0.25)
    raise HarnessError("The local provider stub did not start.")


def main() -> int:
    if sys.platform != "darwin":
        raise HarnessError("This acceptance runner requires the registered macOS simulator host.")
    if not (IOS / "AstraStyle.xcodeproj").exists():
        raise HarnessError("Generate the Xcode project and install the reviewed package lock before running this script.")
    if not shutil.which("docker"):
        raise HarnessError("Docker is required for the local Supabase containers.")
    docker = run(["docker", "info"], timeout=20, check=False)
    if docker.returncode:
        raise HarnessError("Docker is not ready on the local QA runner.")

    fixture_existed = FIXTURE.exists()
    if fixture_existed:
        raise HarnessError("A local QA fixture already exists; refusing to overwrite another run's credentials.")

    temp_root = pathlib.Path(tempfile.mkdtemp(prefix="astra-local-kyra-"))
    os.chmod(temp_root, 0o700)

    def handle_termination(signum, _frame):
        raise HarnessError(f"Local Kyra acceptance interrupted by signal {signum}.")

    signal.signal(signal.SIGTERM, handle_termination)
    signal.signal(signal.SIGINT, handle_termination)
    supabase_dir = temp_root / "supabase"
    supabase_dir.mkdir(mode=0o700)
    project_id = "astra-qa-" + secrets.token_hex(6)
    original_config = (ROOT / "supabase/config.toml").read_text()
    rewritten, count = re.subn(
        r'(?m)^project_id\s*=\s*"[^"]+"',
        f'project_id = "{project_id}"',
        original_config,
        count=1,
    )
    if count != 1:
        raise HarnessError("Could not isolate the temporary local Supabase project name.")
    (supabase_dir / "config.toml").write_text(rewritten)
    (supabase_dir / "migrations").symlink_to(ROOT / "supabase/migrations", target_is_directory=True)
    # Functions are bind-mounted into Docker by `supabase functions serve`.
    # Copy them inside the isolated project because a symlink back to the host
    # checkout is outside the CLI project's container mount.
    shutil.copytree(ROOT / "supabase/functions", supabase_dir / "functions")

    stack_started = False
    user_id = None
    api_url = anon_key = service_key = access_token = refresh_token = None
    fixture_written = False
    child_processes: list[subprocess.Popen] = []
    failed = True
    cleanup_failed = False
    cleanup_verified = False
    stack_stopped = False
    test_passed = False
    result_bundle: pathlib.Path | None = None
    function_env: pathlib.Path | None = None
    try:
        # Keep the standalone/manual harness aligned with the dispatched CI
        # workflow so newly added test sources are present in the generated
        # project before the selected test targets are compiled.
        run(["xcodegen", "generate"], cwd=ROOT / "ios", timeout=60)
        run(
            [
                sys.executable,
                str(ROOT / "scripts/manage_ios_package_resolution.py"),
                "--install",
            ],
            timeout=30,
        )

        # Use the pinned CLI version and a randomized local project ID. Never
        # link, push, or call a hosted project from this harness.
        # A failed `start` can still have created some containers; always run
        # the matching stop command once startup has been attempted.
        stack_started = True
        run([
            "npx", "--yes", f"supabase@{CLI_VERSION}", "start", "--yes",
            "--exclude", EXCLUDED, "--workdir", str(temp_root),
        ], timeout=900)
        run([
            "npx", "--yes", f"supabase@{CLI_VERSION}", "db", "reset",
            "--local", "--no-seed", "--workdir", str(temp_root),
        ], timeout=600)
        local = parse_local_status(temp_root)
        api_url = local["API_URL"].rstrip("/")
        anon_key = local["ANON_KEY"]
        service_key = local["SERVICE_ROLE_KEY"]
        wait_http(api_url + "/auth/v1/health")

        email = f"qa-{secrets.token_hex(8)}@example.invalid"
        password = secrets.token_urlsafe(36)
        headers = {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        }
        status, created = request_json(
            api_url + "/auth/v1/admin/users",
            method="POST",
            headers=headers,
            body={"email": email, "password": password, "email_confirm": True},
        )
        if status not in (200, 201) or not isinstance(created, dict) or not created.get("id"):
            raise HarnessError("Could not create the disposable local auth fixture.")
        user_id = str(uuid.UUID(created["id"]))

        status, session = request_json(
            api_url + "/auth/v1/token?grant_type=password",
            method="POST",
            headers={"apikey": anon_key, "Content-Type": "application/json"},
            body={"email": email, "password": password},
        )
        if status != 200 or not isinstance(session, dict):
            raise HarnessError("Could not obtain the disposable local fixture session.")
        access_token = session.get("access_token")
        refresh_token = session.get("refresh_token")
        if not isinstance(access_token, str) or not isinstance(refresh_token, str):
            raise HarnessError("The local auth fixture did not return a session.")

        item_records = [
            {"user_id": user_id, "name": "Local Navy Test Shirt", "category": "top", "primary_color": "navy"},
            {"user_id": user_id, "name": "Local Stone Test Trousers", "category": "bottom", "primary_color": "stone"},
            {"user_id": user_id, "name": "Local Brown Test Shoes", "category": "shoes", "primary_color": "brown"},
        ]
        status, rows = request_json(
            api_url + "/rest/v1/closet_items?select=id,name",
            method="POST",
            headers={**headers, "Prefer": "return=representation"},
            body=item_records,
        )
        if status not in (200, 201) or not isinstance(rows, list) or len(rows) != 3:
            raise HarnessError("Could not seed the three owned local closet fixtures.")
        item_ids = [str(uuid.UUID(row["id"])) for row in rows]
        item_names = [str(row["name"]) for row in rows]

        stub_token = secrets.token_urlsafe(40)
        stub_port = 18765
        stub_env = os.environ.copy()
        stub_env.update({
            "ASTRA_LOCAL_KYRA_STUB_PORT": str(stub_port),
            "ASTRA_LOCAL_KYRA_STUB_TOKEN": stub_token,
            "ASTRA_LOCAL_KYRA_ITEM_IDS": ",".join(item_ids),
        })
        stub_log = open(temp_root / "provider-stub.log", "w", encoding="utf-8")
        os.chmod(temp_root / "provider-stub.log", 0o600)
        child_processes.append(subprocess.Popen(
            [sys.executable, str(ROOT / "scripts/local_kyra_provider_stub.py")],
            cwd=ROOT,
            env=stub_env,
            stdin=subprocess.DEVNULL,
            stdout=stub_log,
            stderr=stub_log,
            text=True,
        ))
        wait_for_port("127.0.0.1", stub_port)

        function_env = temp_root / "function.env"
        write_private(function_env, (
            f"STYLIST_PROVIDER_API_KEY={stub_token}\n"
            f"ASTRA_LOCAL_STYLIST_PROVIDER_URL=http://host.docker.internal:{stub_port}/v1/responses\n"
        ).encode())
        function_log = open(temp_root / "functions.log", "w", encoding="utf-8")
        os.chmod(temp_root / "functions.log", 0o600)
        child_processes.append(subprocess.Popen(
            [
                "npx", "--yes", f"supabase@{CLI_VERSION}", "functions", "serve", "kyra",
                "--env-file", str(function_env), "--workdir", str(temp_root),
            ],
            cwd=ROOT,
            env=os.environ.copy(),
            stdin=subprocess.DEVNULL,
            stdout=function_log,
            stderr=function_log,
            text=True,
        ))
        wait_function_worker(api_url, anon_key)

        fixture_payload = {
            "user_id": user_id,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "supabase_url": api_url,
            "supabase_anon_key": anon_key,
            "item_names": item_names,
        }
        write_private(FIXTURE, json.dumps(fixture_payload, separators=(",", ":")).encode())
        fixture_written = True

        simulator = run(
            [sys.executable, str(ROOT / "scripts/resolve_ios_simulator.py"), "--runtime", "26.5", "--device", "iPhone 17 Pro"],
            timeout=30,
        ).stdout.strip()
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator):
            raise HarnessError("The pinned iOS 26.5 iPhone 17 Pro simulator could not be resolved.")
        result_bundle = temp_root / "LocalKyraAcceptance.xcresult"
        log_path = temp_root / "xcodebuild.log"
        derived_data = pathlib.Path(
            os.environ.get("ASTRA_LOCAL_QA_DERIVED_DATA", "/tmp/astra-inspiration-build")
        ).expanduser()
        derived_data.mkdir(mode=0o700, parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as log:
            os.chmod(log_path, 0o600)
            result = subprocess.run(
                [
                    "xcodebuild", "test", "-project", "ios/AstraStyle.xcodeproj",
                    "-scheme", "AstraStyle", "-destination", f"id={simulator}",
                    "-derivedDataPath", str(derived_data),
                    "-onlyUsePackageVersionsFromResolvedFile", "-collect-test-diagnostics", "never",
                    "-parallel-testing-enabled", "NO",
                    "-resultBundlePath", str(result_bundle),
                    "-only-testing:AstraStyleTests/AnalyticsEventPrivacyTests",
                    "-only-testing:AstraStyleTests/AstraSupabaseClientFactoryTests",
                    "-only-testing:AstraStyleUITests/LocalKyraAcceptanceUITests",
                ],
                cwd=ROOT,
                text=True,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
            )
        if result.returncode:
            raise HarnessError("The local Kyra UI acceptance test failed; inspect the sanitized xcresult evidence.")
        if not result_bundle.exists():
            raise HarnessError("Xcode did not produce a result bundle for the selected UI test.")

        # Ensure this targeted suite executed one test and did not silently
        # pass because it was skipped. xcresult data contains no fixture JWTs.
        tests_json = run([
            "xcrun", "xcresulttool", "get", "test-results", "tests",
            "--path", str(result_bundle), "--compact",
        ], timeout=60).stdout
        try:
            report = json.loads(tests_json)
        except json.JSONDecodeError as error:
            raise HarnessError("Could not parse the local Kyra XCTest result report.") from error
        matching_results = []
        privacy_results = []

        def visit(node):
            if not isinstance(node, dict):
                return
            name = node.get("name", "")
            if name.split("(", 1)[0] == "testAskKyraRendersOnlyFixtureOwnersClosetItems":
                matching_results.append(node.get("result"))
            if "AnalyticsEventPrivacyTests" in name or name in {
                "eventPayloadsStayNonSensitive",
                "adversarialCategoricalInputsAreSanitized",
                "catalogRetailersUseCanonicalIDs",
            }:
                privacy_results.append(node.get("result"))
            for child in node.get("children", []):
                visit(child)

        for node in report.get("testNodes", []):
            visit(node)
        if matching_results != ["Passed"] or not privacy_results or any(value != "Passed" for value in privacy_results):
            raise HarnessError("The result bundle did not prove the local Kyra UI and analytics privacy tests passed.")
        test_passed = True
        failed = False
        print("Local Kyra acceptance passed against disposable local Supabase and the deterministic provider stub.")
        print("No production Supabase endpoint or paid provider was used.")
        return 0
    finally:
        if user_id and api_url and service_key:
            try:
                cleanup_headers = {
                    "apikey": service_key,
                    "Authorization": f"Bearer {service_key}",
                    "Content-Type": "application/json",
                }
                status, _ = request_json(
                    api_url + "/auth/v1/admin/users/" + urllib.parse.quote(user_id),
                    method="DELETE",
                    headers=cleanup_headers,
                    timeout=10,
                )
                if status not in (200, 204):
                    cleanup_failed = True
                    print("WARNING: local fixture account cleanup did not confirm; local project will be stopped.", file=sys.stderr)
                else:
                    status, _ = request_json(
                        api_url + "/auth/v1/admin/users/" + urllib.parse.quote(user_id),
                        headers=cleanup_headers,
                        timeout=10,
                    )
                    auth_deleted_verified = status == 404
                    if not auth_deleted_verified:
                        cleanup_failed = True
                        print("WARNING: local auth fixture remains readable after deletion; local project will be stopped.", file=sys.stderr)
                    status, rows = request_json(
                        api_url + "/rest/v1/closet_items?select=id&user_id=eq." + urllib.parse.quote(user_id),
                        headers=cleanup_headers,
                        timeout=10,
                    )
                    rows_empty = status == 200 and rows == []
                    if not rows_empty:
                        cleanup_failed = True
                        print("WARNING: local closet fixture rows remain after account deletion; local project will be stopped.", file=sys.stderr)
                    cleanup_verified = auth_deleted_verified and rows_empty
            except Exception:
                cleanup_failed = True
                print("WARNING: local fixture cleanup request failed; local project will be stopped.", file=sys.stderr)
        if fixture_written:
            FIXTURE.unlink(missing_ok=True)
            try:
                FIXTURE.parent.rmdir()
            except OSError:
                pass
        for process in reversed(child_processes):
            if process.poll() is None:
                process.send_signal(signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        if function_env is not None:
            function_env.unlink(missing_ok=True)
        if stack_started:
            stopped = run([
                "npx", "--yes", f"supabase@{CLI_VERSION}", "stop", "--no-backup", "--yes",
                "--workdir", str(temp_root),
            ], timeout=180, check=False)
            if stopped.returncode:
                cleanup_failed = True
                print("WARNING: isolated Supabase stack did not stop cleanly; check runner containers.", file=sys.stderr)
            else:
                stack_stopped = True

        # Preserve only the test result bundle and a credential-free summary.
        # The function env file, local status output, session fixture, and raw
        # service logs are never copied into CI artifacts.
        evidence_raw = os.environ.get("ASTRA_LOCAL_QA_EVIDENCE_DIR")
        if evidence_raw:
            evidence_dir = pathlib.Path(evidence_raw).resolve()
        else:
            evidence_dir = pathlib.Path(tempfile.gettempdir()) / f"astra-local-kyra-evidence-{os.getpid()}"
        if evidence_dir == ROOT or ROOT in evidence_dir.parents:
            cleanup_failed = True
            print("WARNING: evidence directory must be outside the repository.", file=sys.stderr)
        else:
            evidence_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
            if result_bundle is not None and result_bundle.exists():
                shutil.copytree(result_bundle, evidence_dir / "LocalKyraAcceptance.xcresult")
            report = {
                "supabase_cli_version": CLI_VERSION,
                "backend": "disposable local Supabase stack",
                "provider": "deterministic local Responses stub",
                "selected_test": "AstraStyleUITests/LocalKyraAcceptanceUITests/testAskKyraRendersOnlyFixtureOwnersClosetItems",
                "test_passed": test_passed,
                "fixture_owner_deleted_and_rows_empty": cleanup_verified,
                "isolated_stack_stopped": stack_stopped,
                "hosted_supabase_called": False,
                "paid_provider_called": False,
                "recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            write_private(evidence_dir / "acceptance.json", json.dumps(report, indent=2).encode())
            print(f"Credential-free acceptance evidence: {evidence_dir}")

        # The xcresult and sanitized report are preserved separately above;
        # discard temporary env files and raw logs regardless of outcome.
        shutil.rmtree(temp_root, ignore_errors=True)
        if cleanup_failed and not failed:
            raise HarnessError("Local fixture deletion could not be verified; the isolated project was stopped.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except HarnessError as error:
        print(f"Local Kyra acceptance: {error}", file=sys.stderr)
        sys.exit(1)
