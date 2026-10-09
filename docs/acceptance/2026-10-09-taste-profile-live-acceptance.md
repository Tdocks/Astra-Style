# Hosted taste-answer persistence acceptance

Date: 2026-10-09
Project: `anutsdzbxycaavmmkewo` (production)
Harness: `hosted_taste_answers_acceptance.ts`
Result JSON: `hosted-acceptance-result.json`

## Cases

| Case | Result |
| --- | --- |
| Anonymous owner submits first-run onboarding with three catalog-backed quiz choices and a three-axis vector | `POST /functions/v1/profile/complete-onboarding` returned 200. Caller-scoped readback found the exact three answers and exact vector in one `style_profiles` row. |
| Same owner submits refinement through ordinary authenticated PostgREST upsert | Returned 200. Readback matched all 16 answer choices and all eight vector dimensions. |
| Owner reads peer's style profile | Returned 200 with zero rows. |
| Owner attempts to upsert peer's quiz answers/vector | Returned 403; peer's own readback remained unchanged with zero quiz answers. |
| Account cleanup | Both disposable anonymous accounts accepted `DELETE /functions/v1/account` with 202. No cleanup failures. |

The run used no image bytes, photo uploads, or provider calls. It used only synthetic anonymous accounts and preference metadata. The owner fixture UUID is `74a9d33a-f71c-4b0b-a606-307bdcba6633`; its deletion receipt is `82047ab0-5f55-4fd4-aacd-df4a475f3aec`. The peer fixture UUID is `917b6afe-cbdc-4a43-bfc9-6b126c94f7d6`; its deletion receipt is `93e80c00-aaeb-4fee-99f5-c1a93a0f1eb4`.

## Limits

Root independently queried the production database after cleanup: both fixture
identities, profiles and style profiles had zero remaining rows, and both
deletion jobs were completed.

Native verification passed the full unit suite (1,101 Swift Testing tests and
33 XCTest tests). `StyleQuizRefinementUITests` also passed the complete 16-choice
Profile flow, save eligibility, and failed-DNA retry without a second preference
write on iPhone Simulator. These checks do not establish a blinded human review
of the quiz imagery or real-device accessibility acceptance.
