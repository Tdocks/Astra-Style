#!/usr/bin/env python3
"""Exercise scanner reservation races in a disposable astra_ database."""
import concurrent.futures
import json
import subprocess
import sys
import threading
import uuid

database = sys.argv[1] if len(sys.argv) == 2 else ""
if not database.startswith("astra_") or not all(c.isalnum() or c == "_" for c in database):
    raise SystemExit("Supply the astra_ scratch DB created by the RLS harness.")
command = ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-d", database]


def sql(query, *, check=True):
    return subprocess.run(command, input=query, text=True, capture_output=True, check=check, timeout=20)


def race(queries):
    barrier = threading.Barrier(len(queries))

    def run(query):
        barrier.wait(timeout=10)
        return sql("set role service_role; " + query, check=False)

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(queries)) as pool:
        return list(pool.map(run, queries))


owner, competing_owner = str(uuid.uuid4()), str(uuid.uuid4())
source = f"users/{owner}/closet/{uuid.uuid4()}.jpg"
sources = [f"users/{competing_owner}/closet/{uuid.uuid4()}.jpg" for _ in range(8)]
config = json.loads(sql("select row_to_json(c) from public.closet_cutout_config c;").stdout)
try:
    sql(f"insert into auth.users(id,email) values('{owner}','{owner}@cutout-race.invalid'),"
        f"('{competing_owner}','{competing_owner}@cutout-race.invalid');")
    for path in [source] + sources:
        sql(f"insert into storage.objects(bucket_id,name) values('user-content','{path}');")
    sql("update public.closet_cutout_config set enabled=true,daily_limit=1,monthly_limit=1;")
    results = race([f"select public.claim_closet_cutout('{owner}','{source}','same-key');"] * 8)
    assert all(result.returncode == 0 for result in results), [result.stderr for result in results]
    claims = [json.loads(result.stdout) for result in results]
    assert sum(claim['state'] == 'reserved' for claim in claims) == 1, claims
    assert sum(claim['state'] == 'pending' for claim in claims) == 7, claims
    token = next(claim['token'] for claim in claims if claim['state'] == 'reserved')
    results = race([f"select public.begin_closet_cutout('{token}');"] * 8)
    assert sum(result.returncode == 0 for result in results) == 1
    assert all(result.returncode == 0 or 'cutout_dispatch_unavailable' in result.stderr for result in results)
    results = race([f"select public.claim_closet_cutout('{competing_owner}','{path}','key-{index}');"
                    for index, path in enumerate(sources)])
    assert sum(result.returncode == 0 for result in results) == 1
    assert all(result.returncode == 0 or 'cutout_quota_exhausted' in result.stderr for result in results)
    count = sql(f"select count(*) from public.closet_cutout_requests where user_id='{competing_owner}';").stdout.strip()
    assert count == '1', count
    print("8 duplicate claims: 1 reservation, 7 pending; 8 dispatches: 1 accepted; 8 distinct claims at cap 1: 1 accepted, 7 quota failures.")
finally:
    for path in [source] + sources:
        sql(f"delete from storage.objects where bucket_id='user-content' and name='{path}';")
    sql(f"delete from auth.users where id in ('{owner}','{competing_owner}');")
    enabled = 'true' if config['enabled'] else 'false'
    sql(f"update public.closet_cutout_config set enabled={enabled},daily_limit={config['daily_limit']},monthly_limit={config['monthly_limit']};")
