# Populated personal-data export acceptance — 2026-10-09

## Fixture and request

Ran against hosted project `anutsdzbxycaavmmkewo` using the deployed `profile`
function (version 18). Created two disposable, confirmed synthetic accounts and
populated matching rows for profile/style/body/lifestyle, closet item/image,
outfit/item/wear, and Kyra thread/message groups, plus style feedback and
memory. Fixture values were synthetic markers only; no provider or image-file
request was made. Both exports were requested through `GET
/functions/v1/profile/export-data` with the respective user's access token.

## Results

Both owner-scoped exports returned HTTP 200, `Cache-Control: no-store`, and
`Vary: Authorization`. Each contained one row in each populated table:

| Group | Tables verified |
|---|---|
| Profile | `profiles`, `style_profiles`, `body_profiles`, `lifestyle_profiles` |
| Closet | `closet_items`, `closet_item_images` |
| Outfits | `outfits`, `outfit_items`, `outfit_wears` |
| Kyra and feedback | `kyra_threads`, `kyra_messages`, `style_feedback`, `style_memories` |

The caller's synthetic marker appeared in their export; the peer marker and
peer owner ID did not. The reverse check passed for the peer export. The export
contained no auth user metadata, access/refresh tokens, or service-key fields.
The export response was checked in memory; no profile, conversation, or other
fixture contents were written to the report or terminal.

## Cleanup

Both fixtures were deleted through the normal authenticated `DELETE
/functions/v1/account` route, which returned HTTP 202. The deletion receipts
reached completion: a service-role verification read found both Auth users
absent (HTTP 404) and zero rows for each owner across all 13 populated tables.
Root independently confirmed zero Auth/profile/closet/outfit/Kyra rows and
two completed deletion jobs with SQL. Fixture identifiers:

- Owner fixture: `bac89f7a-a2a7-4043-84a6-7335426f1a3a`
- Peer fixture: `8089213a-8dc3-4144-a8b5-74c78b5aa9c7`
- Owner deletion receipt: `1222ca19-9462-460c-868f-aae9ddd6aee2`
- Peer deletion receipt: `de1b4020-a629-44ad-a744-ba7cc073cdbc`

One disposable identity from a failed setup attempt was removed through the
Auth Admin API before the acceptance run. It was not used in either export.

## Scope

This closes populated export coverage for the profile, closet, outfit, and Kyra
content groups in the acceptance criteria. It does not claim that private
Storage image bytes are included; the export intentionally provides a scoped
manifest of referenced object paths instead.
