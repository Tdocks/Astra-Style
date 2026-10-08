# Home inspiration — device acceptance

Build: 1.0.0 (12), 2026-10-08. Backend: Studio v8.

Simulator verification used mock services/images. These checks require a signed-in production account and the real provider:

1. Open Home → Get today's inspiration with an empty closet. Generate a coordinated image without uploading a selfie.
2. Confirm quiz preferences influence the look. Enable weather/calendar on Home and confirm the inspiration screen includes current conditions and today's events. Turn permissions off and confirm it reports missing context.
3. Ask for a more casual look, a dressier look, and date night. Confirm each edit preserves the previous composition where appropriate and makes the requested change. Reroll and confirm a distinct option appears.
4. Open Style an outfit from my closet. Confirm the proposed pieces exist in your closet and are wearable. Expand Choose or swap pieces; replace the pants and render again. Confirm the selected pieces, colors and cuts are represented, with no invented additions. Image fit/color remain estimates.
5. Open the saved image in Style Studio, then delete it. Confirm history and private image deletion both work.
6. Disconnect during generation, then reconnect and Check again or resume from Studio. Confirm the UI recovers without an endless spinner. A failed provider render can use its saved retry; new rerolls/edits use image allowance.
7. Open Talk through this with Kyra. Confirm live styling replies work and reference the provided closet/style/day context.
8. Check light/dark appearance and large text. Confirm controls remain reachable and the estimate/allowance notices are readable.

Still separate: real-device camera and voice permissions, sandbox purchases, signed App Store notification acceptance, and counsel's legal-page inputs. This checklist is not an outside-user readiness approval.
