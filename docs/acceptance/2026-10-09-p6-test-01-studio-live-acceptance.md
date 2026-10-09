# P6-TEST-01 — Studio generation and retry acceptance

**Date:** 2026-10-09  
**Scope:** `P6-TEST-01` only. This evidence does not close Studio visual-fidelity, high-resolution, or device-acceptance work.

## Live success path

Ran `supabase/functions/studio/hosted_acceptance.ts` once against the deployed Studio function using a newly created synthetic anonymous account. The request was an inspiration flat lay with no selfie, reference photo, or real-person image. It asked for a smart-casual fall outfit in navy, olive, and warm neutrals.

- The live OpenAI request was accepted once and observed through `queued → generating → complete`.
- The completed row identified provider `openai`; the synthetic owner's trial usage increased by exactly one.
- The owner downloaded the private result as a PNG. Its dimensions were 1024 × 1536 and its file size passed the harness's 50 KB minimum. Visual inspection confirmed a coherent flat lay with navy and olive layers, denim, shoes, and accessories on a neutral background.
- The hosted harness used its normal account `DELETE` path. It received HTTP 200/202, then confirmed Auth no longer recognized the synthetic identity. Storage logs recorded one `storage.object.delete_many` operation; an independent post-delete SQL check confirmed zero `storage.objects` rows for this generation.

Synthetic fixture identifiers for independent cleanup/audit correlation:

| Record | Identifier |
|---|---|
| Synthetic Auth owner | `87973241-8cac-4981-b08f-156ca972dfb9` |
| Generation | `953afa8a-6628-4338-9262-a1c713682cb5` |
| Account deletion receipt | `2db2d868-0214-4d45-80c0-4fa9947a7216` |
| Generation enqueue request | `3dcb7856-c1b8-406e-8978-def2e0c1d5ca` |
| Account deletion request | `52d24c33-c6c5-48ab-8179-e01cc85734a1` |

The account deletion logs recorded both `account_delete.accepted` and `account_delete.cascade_complete` for the deletion receipt above. The protected PNG was reviewed from `/tmp/astra-studio-live-acceptance-40bee41c-66eb-43df-9d96-7f32655afa88.png`; the image is intentionally not committed.

## Controlled retry path

Ran the deterministic injected-provider test:

```text
deno test -A --filter='controlled live-provider failure retries the same trial to completion without a new quota check' studio/handler_test.ts
```

It passed and covered `queued → generating → failed → retry queued → generating → complete`. The original failed row remained as the audit record, the retry reused its allowance, and the test's quota-check count stayed at one. This is a controlled provider failure; it does not induce a failure or extra billable request against the hosted provider.

## Remaining Studio acceptance

This closes the job-polling lifecycle and simulated retry criteria of `P6-TEST-01`. It does not certify identity retention or garment fidelity on a real person, the premium high-resolution export path, device-specific behavior, or the remaining preset/gallery requirements. Those remain separately tracked as partial work.
