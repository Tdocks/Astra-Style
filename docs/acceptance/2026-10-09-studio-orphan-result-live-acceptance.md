# Studio orphan-result cleanup hosted acceptance — 2026-10-09

**Project:** `astra-style` (`anutsdzbxycaavmmkewo`). **Provider calls:** none.

The deployed Edge Function batch passed 1,030 Deno tests plus formatting and lint checks before this hosted acceptance. The hosted evidence below is limited to the explicitly identified synthetic fixtures and worker branches.

## Fixture and first worker pass

The due orphan queue was empty, there were no expired Studio-retention candidates, and the fixture owner had no prior Studio rows. A confirmed disposable Auth account was created through Auth Admin, signed in using its caller token, and uploaded three copies of the repository's non-person AppIcon PNG to canonical owner-scoped result paths. The fixture included one `complete` generation and two `queued` generations, each with a valid allowance and one exact orphan-cleanup ledger entry.

Synthetic owner: `62ac07df-ef12-4315-b82e-b867014f268d`.

| Purpose | Generation ID |
| --- | --- |
| Complete result, must preserve | `6b16a042-7c2a-4e9b-9a62-92b7ff902521` |
| Active queued job, must defer | `75cb9444-6df1-46f3-9d31-ed63f14df1e7` |
| Job later removed by account deletion | `27c77033-a9db-4080-b215-4b0c6f6ec277` |

The Vault-backed scheduled `studio-retention` endpoint returned HTTP 200 with `orphanCompleted: 1` and `orphanRetrying: 2`. Independent SQL showed that the complete generation kept its row and image while its stale cleanup ledger entry was removed; both queued generations kept their rows and images with one deferred ledger entry each. A caller-JWT download check read all three images and byte-compared them with the local PNG asset.

## Deletion and orphan cleanup pass

The account was removed through the normal `DELETE /account` flow. Its deletion receipt is `f03d7de9-9164-4fac-a34d-8e7951f86802`; the receipt reached `completed` and the Auth identity was removed. Account deletion removed the generation and allowance rows and the three Storage objects, while the two deferred cleanup ledger rows survived.

Only those two fixture ledger rows were made immediately eligible for the second pass. Before invoking the worker, SQL confirmed there were exactly two due orphan rows, both belonged to this fixture, with zero unrelated orphan rows and zero expired Studio-retention candidates. The Vault-backed endpoint returned HTTP 200 with `orphanCompleted: 2` and `orphanRetrying: 0`. Final independent SQL verified zero fixture ledger rows, generations, allowances, Storage objects, or Auth users.

This exercises complete-result preservation, active-job deferral, the durable ledger surviving owner/job deletion, and retry cleanup after normal account erasure. The worker was only invoked with empty unrelated candidate queues; no provider calls, real-user changes, or scheduler secrets were used or recorded.

## Existing-object removal while the job remains

A second confirmed synthetic owner uploaded three more AppIcon PNGs. One canonical path was attached to a `failed` Studio generation with one exact orphan ledger row. Before the worker pass, the due queue contained exactly that one fixture row and no unrelated due rows; there were no expired Studio-retention candidates. The retention endpoint returned HTTP 200 with `orphanCompleted: 1` and `orphanRetrying: 0`.

Before account deletion, independent SQL showed the `failed` generation row still existed, its `storage.objects` result count was zero, and its orphan ledger count was zero. A caller-JWT download returned the Storage missing-object response (HTTP 400 with Storage `statusCode: 404`, `error: not_found`). This verifies the worker removed an existing object while retaining the failed job row. The two extra uploaded paths, which had no fixture generation rows, were removed by normal account deletion.

Synthetic removal-test owner: `c440a995-d17d-4690-8af7-eaa3af6bb73d`; failed generation: `0bed65d7-f2ef-476f-af5b-a635c9d38b8e`. The normal account deletion receipt is `76970e4f-6f33-4b52-ba63-8fdf10831097`. It reached `completed`, and final independent SQL found zero fixture ledger, generation, allowance, Storage object, or Auth rows.
