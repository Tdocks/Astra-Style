# Studio high-quality export live acceptance

Date: 2026-10-09

## Result

One synthetic, no-person Studio inspiration draft was generated, followed by exactly one Premium export request. The export completed as a child generation and its private image downloaded successfully with the synthetic owner session. No retries or additional provider submissions were made.

The parent generation remained complete and unchanged. The child recorded `resolution=hi_res`, its source generation ID, and its own canonical owner-scoped result path. The child completed and retained its allowance reservation.

## Measured output

The draft and exported child images are both 1024×1536 pixels. The child image is 3,076,943 bytes. Visual inspection found a coherent, no-person menswear flat-lay with the requested jacket, sweater, shirt, denim, shoes, messenger bag, and beanie. The high-quality child looked cleaner and more evenly spaced, but did not have more pixels than the draft.

This proves the high-quality provider tier, child-job lifecycle, lineage, owner-authorized private download, and allowance behavior. It does **not** prove a higher pixel resolution, a 2K output, or the full fidelity of clothing on a person. Do not describe this run as a 2K or pixel-resolution export. The provider adapter currently uses `gpt-image-1.5`, fixed portrait size `1024x1536`, and quality `medium` for draft versus `high` for `hi_res`.

## Synthetic fixture and cleanup

- Owner: `7edd61ce-b2f0-45f4-90dd-e12b133dd038`
- Source generation: `b4ffb6fd-4aee-49a8-8804-25b57bbe32cc`
- Export child: `5ea197dc-6b9b-4282-9758-473679e9905b`
- Temporary sandbox subscription fixture: `b0c96097-06f9-4867-bdd1-d983c4793c42`
- Account deletion receipt: `c78c0070-6765-4dfd-b6e3-0848d4644864`

Normal account deletion completed. Independent SQL readback returned zero rows for the owner in `auth.users`, `public.profiles`, `public.subscriptions`, `public.studio_generations`, `public.studio_allowances`, and `storage.objects` under the owner prefix.

## Remaining work

The UI's “high-resolution” wording should describe a higher-quality export unless a provider capable of larger output dimensions is configured and verified. Keep the true higher-pixel-resolution requirement open. No additional provider request was made to investigate it.
