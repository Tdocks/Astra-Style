# ASTRA STYLE — iOS MASTER BUILD SPECIFICATION

**Product:** Astra Style  
**Platform:** Native iPhone app, iOS 18+  
**Primary interface:** SwiftUI  
**Companion:** Kyra, pronounced “KEER-uh”  
**Positioning:** A premium personal stylist and wardrobe operating system for men  
**Visual direction:** Black marble, bone, charcoal, champagne gold, editorial menswear photography  
**Document purpose:** A single-source implementation specification intended for Claude Code, Grok Build, Cursor, Codex, Gemini, or a human engineering team.

---

## 1. PRODUCT NORTH STAR

Astra Style helps a man become the best-dressed version of himself over time. It is not primarily a shopping app, digital closet, outfit randomizer, or generic AI chatbot. It is a personal styling system that understands the user, his wardrobe, body, lifestyle, budget, calendar, climate, habits, and long-term image goals.

### Core promise

> Open Astra Style each morning and Kyra will tell you what to wear, why it works, and what—if anything—you should buy next.

### Primary outcomes

1. Reduce daily clothing decisions.
2. Increase confidence and outfit quality.
3. Make existing clothes more useful.
4. Prevent redundant or low-value purchases.
5. Create visual previews before users buy.
6. Build a coherent wardrobe over months and years.
7. Teach style without overwhelming the user.

### Differentiating system

The core moat is the **Wardrobe Graph**. Every owned garment, accessory, outfit, occasion, preference, and candidate purchase becomes a node or relationship. Astra Style can quantify which purchase unlocks the most outfits, identify wardrobe bottlenecks, track cost per wear, and create a deliberate progression plan.

---

## 2. BRAND SYSTEM

### Brand hierarchy

- **Astra Style:** The product and platform.
- **Kyra:** The user-facing stylist and companion.
- **Style Studio:** Visual try-on and outfit visualization.
- **Wardrobe Graph:** Recommendation and compatibility engine.
- **Kyra’s Daily Brief:** Home experience.
- **Kyra’s Picks:** Personalized product recommendations.
- **Style Journey:** Long-term progression and monthly reports.

### Voice

Kyra is warm, intelligent, composed, opinionated, and direct. She behaves like a premium stylist, not a customer-service bot.

Kyra should:

- Explain recommendations briefly.
- Tell users not to buy redundant items.
- Respect budget and lifestyle.
- Learn from feedback.
- Avoid shallow praise.
- Offer one strong recommendation before multiple alternatives.
- Use natural language such as “I’d wear…” and “I would skip this one.”

Kyra should not:

- Mention that she is an AI unless legally required.
- Overuse fashion jargon.
- Shame body type, budget, age, or existing wardrobe.
- Claim certainty about fit from insufficient evidence.
- Give generic compliments after every action.

### Example tone

- “I’d wear the olive knit polo, stone trousers, and white sneakers today. It fits the weather and moves cleanly from work to dinner.”
- “Skip the second black bomber. It adds very little to what you already own.”
- “The jacket works, but the current length shortens your torso. A slightly shorter cut would balance you better.”

---

## 3. DESIGN SYSTEM

### Visual principle

The app should feel like a luxury stylist’s editorial notebook: dark, restrained, tactile, and calm. Technology remains invisible.

### Color tokens

#### Dark mode — default

- `backgroundPrimary`: `#0D0D0D`
- `backgroundSecondary`: `#151515`
- `surfaceElevated`: `#1B1B1B`
- `surfaceMarble`: asset-based near-black marble texture
- `textPrimary`: `#F7F3EA`
- `textSecondary`: `#B9B3A8`
- `textMuted`: `#88847C`
- `accentChampagne`: `#D7B46A`
- `accentChampagnePressed`: `#B8944D`
- `divider`: `#2A2927`
- `successOlive`: `#69745D`
- `warningAmber`: `#A98652`
- `destructive`: `#B65F59`

#### Light mode

- `backgroundPrimary`: `#F8F5EF`
- `backgroundSecondary`: `#EFEAE1`
- `surfaceElevated`: `#FFFFFF`
- `textPrimary`: `#111111`
- `textSecondary`: `#56514B`
- `textMuted`: `#746E66`
- `accentChampagne`: `#AB8545`
- `divider`: `#DDD6CB`

> **Revised 2026-07-30.** `textMuted` (both schemes, above) and light-mode `accentChampagne` were
> corrected from this spec's original values (dark `textMuted` `#77736C`; light `textMuted`
> `#8C867D`; light `accentChampagne` `#B8914E`) to what the app actually ships. The original values
> failed WCAG AA against every surface they appear on — full ratios, methodology, and the shipped
> replacements are in `docs/07-design-system.md` §3 ("Accessibility contrast analysis"). This spec
> is the source of truth per `CLAUDE.md`, so the correction lives here rather than being left as a
> permanently-failing acceptance criterion (`P1-DS-01`) pointing at values nobody should restore.
> `scripts/check_contrast.py` enforces the shipped values against `AstraColor.swift` directly, not
> against this document, so it was unaffected by this edit and remains the authority on whether a
> token passes contrast; this note explains *why* the values are what they are.

### Typography

Use system-safe licensed fonts in implementation.

- Editorial display: `New York` or bundled licensed serif.
- UI text: `SF Pro`.
- Logo wordmark remains a separate vector asset.

Text styles:

- `displayXL`: 42 pt serif, semibold
- `displayL`: 34 pt serif, semibold
- `title1`: 28 pt serif
- `title2`: 22 pt serif
- `headline`: 17 pt sans, semibold
- `body`: 16 pt sans
- `callout`: 15 pt sans
- `caption`: 12 pt sans
- `micro`: 10 pt sans, uppercase, tracking 1.5

### Layout

- Base spacing unit: 4 pt.
- Standard page padding: 20 pt.
- Card corner radius: 18 pt.
- Button corner radius: 14 pt.
- Compact chip radius: capsule.
- Minimum tap target: 44 × 44 pt.
- Use soft shadows only in light mode.
- Use subtle 1 px borders in dark mode.

### Motion

- Standard transition: 220 ms ease-in-out.
- Hero cards: matched geometry animation.
- Outfit alternatives: horizontal paging with spring settling.
- Kyra orb/avatar: subtle breathing animation, never distracting.
- Haptics: selection for outfit swaps; success for saved closet scan; warning for destructive actions.
- Respect Reduce Motion.

### Iconography

Use SF Symbols with rounded or regular weight. Avoid cartoon icons. Gold indicates active state; bone/gray indicates inactive.

### Marble

Marble is a brand texture, not a universal background. Use it on:

- Splash screen.
- App icon.
- Paywall hero.
- Select premium cards.
- Kyra transition surfaces.

Do not place marble behind dense text.

---

## 4. APP INFORMATION ARCHITECTURE

### Primary tab bar

1. **Home**
2. **Closet**
3. **Studio**
4. **Discover**
5. **Profile**

**(Amended 2026-08-22, ADR 0015.)** The five tabs remain the information
architecture. Until Studio and Discover serve the Wardrobe Graph, dogfood
chrome is Home, Closet, and Profile. Unfinished tabs must not sit in the bar
advertising "Not built yet" every session.

### Global actions

- Ask Kyra.
- Scan an item.
- Create outfit.
- Add a planned occasion.
- Search.

### Navigation model

Use `NavigationStack` per tab with independent paths. Preserve tab navigation state. Present camera, paywall, authentication, onboarding, and full-screen visual generation as modal flows.

---

## 5. CORE USER FLOWS

### 5.1 First launch

1. Splash animation: marble background, gold Astra mark.
2. Wordmark: ASTRA STYLE.
3. Tagline: “Your style. Your journey. Your best self.”
4. Continue.
5. Sign in with Apple or email. **(Amended 2026-08-06, ADR 0014: an account is required; guest mode is removed.)**
6. Kyra introduction.
7. Style identity onboarding. **(Required. ADR 0015 first-run keeps this as the one required answer.)**
8. Taste-snapshot visual quiz — at most three comparisons. **(Amended 2026-08-22, ADR 0015. Catalog remains 12–20 pairs; the front door asks three. Remaining axes, including silhouette, are deferred until the closet has signal.)**
9. Add first closet items (photo-first, one to three) or skip.
10. Generate initial Style DNA.
11. Show first Daily Brief.

Body/fit, appearance, lifestyle, goals, and optional reference capture remain
specified screens. They are **not** in the first-run sequence (ADR 0015). They
may be asked later; they must not block Home.

### 5.2 Daily use

1. App opens to Kyra’s Daily Brief.
2. Shows weather, schedule context, and primary outfit.
3. User can accept, swap, explain, edit, save, or mark worn.
4. User can ask Kyra for alternatives.
5. App records wear and feedback.

### 5.3 Closet scan

1. Tap scan.
2. Camera guidance requests garment on neutral background.
3. Capture front; optional back, label, and detail.
4. Device performs segmentation and initial color/category extraction.
5. Server analysis suggests category, subtype, brand, color, pattern, material, condition, and fit.
6. User reviews and corrects.
7. Background is removed and item image normalized.
8. Item enters wardrobe graph.
9. App reports newly unlocked outfits.

### 5.4 Outfit generation

1. Choose occasion or natural-language request.
2. Kyra uses weather, schedule, wardrobe, laundry availability, fit, and preferences.
3. Generate 3 ranked outfits.
4. Primary recommendation includes a concise reason.
5. User can lock items and regenerate the rest.
6. User can visualize the outfit on himself.
7. Save, schedule, wear, share, or shop missing items.

### 5.5 Shopping decision

1. User opens recommended product or pastes a link.
2. App analyzes fit with wardrobe.
3. Shows compatibility score, duplicate risk, estimated new outfits, missing-use cases, expected cost per wear, and alternatives.
4. Kyra gives a clear verdict: buy, consider, wait, or skip.
5. Affiliate link opens retailer.
6. User can add to wishlist or mark purchased.

### 5.6 Style Studio

1. Select saved selfie/avatar.
2. Select outfit, individual products, or style theme.
3. Generate visual estimate.
4. Clearly label generated imagery as an approximation.
5. Compare options side by side.
6. Save to lookbook, ask Kyra, or shop.

---

## 6. SCREEN-BY-SCREEN SPECIFICATION

### 6.1 Splash

Components:

- Full-screen marble texture.
- Center gold Astra monogram.
- Fade in wordmark.
- Optional tagline.
- 1.4-second maximum before routing.

Routing:

- Authenticated and onboarded → Home.
- Authenticated, onboarding incomplete → resume onboarding.
- No session → Welcome.

### 6.2 Welcome/authentication

Actions:

- Continue with Apple.
- Continue with email.
- Terms and Privacy links.

**Amended 2026-08-06 — ADR 0014.** "Explore demo" and the guest-mode
restrictions that followed it are removed: an account is required before
onboarding. The trial path they described was never reachable — a guest
could not scan, could not receive a Style DNA, and could not be given an
outfit, because all three are server capabilities a guest deliberately had
no identity for. The free-tier closet cap on a *signed-in* user
(`FreeTierLimits`) is a separate rule and is unaffected.

### 6.3 Kyra introduction

Copy:

> “I’m Kyra. I’ll learn your wardrobe, your preferences, and the way you live—then help you dress with intention.”

Avatar options should be configurable later. Initial build uses an elegant abstract portrait, not photorealistic human deception.

### 6.4 Onboarding — Style goals

Multi-select:

- Dress better day to day.
- Build a complete wardrobe.
- Improve professional image.
- Prepare for dates and social events.
- Find a signature style.
- Shop more intelligently.
- Dress for a changing body.
- Pack and travel better.

### 6.5 Onboarding — Style identity

Visual card selections:

- Modern Heritage.
- Quiet Luxury.
- Smart Casual.
- Minimalist.
- Luxury Streetwear.
- Rugged Utility.
- Classic Americana.
- European Summer.
- Executive.
- Creative.

Ask users to choose three, then rank one primary.

### 6.6 Onboarding — Measurements and fit

Fields:

- Height.
- Weight optional.
- Chest.
- Waist.
- Inseam.
- Neck.
- Shoe size.
- Typical shirt size.
- Typical trouser size.
- Preferred fit: slim, tailored, regular, relaxed, oversized.
- Fit issues: broad chest, short torso, long legs, large thighs, etc.

Allow “I don’t know.” Provide camera-assisted measurement as future beta, not a guaranteed measurement tool.

### 6.7 Onboarding — Appearance profile

Optional:

- Skin undertone.
- Hair color.
- Eye color.
- Facial hair.
- Glasses.
- Tattoos visibility.
- Reference selfies.

Explain why each is used and allow omission.

### 6.8 Onboarding — Lifestyle

- Occupation category.
- Dress code.
- Typical week.
- Common occasions.
- Climate location permission.
- Laundry cadence.
- Travel frequency.
- Religious/service attire needs.
- Preferred stores and brands.
- Monthly or annual clothing budget.
- Sustainability preference.

### 6.9 Onboarding — Style preference quiz

Show paired images. Ask which outfit the user would rather wear. The **catalog**
holds 12–20 comparisons covering:

**(Amended 2026-08-22, ADR 0015.)** First-run asks at most three of those
comparisons (a taste snapshot). A sparse vector is a valid Style DNA input;
unasked axes stay absent, never faked. Infer, across the catalog:

- Color tolerance.
- Formality.
- Silhouette.
- Texture.
- Branding/logo tolerance.
- Trend tolerance.
- Accessory preference.
- Contrast preference.

### 6.10 Style DNA result

Show:

- Primary style identity.
- Secondary influences.
- Preferred palette.
- Best silhouette direction.
- Signature item opportunities.
- Initial wardrobe priorities.

Allow user to edit and regenerate.

### 6.11 Home — Kyra’s Daily Brief

Header:

- “Good morning, [Name].”
- Kyra avatar button.
- Weather and location.
- Schedule summary if permission granted.

Hero card:

- Large generated/editorial outfit image.
- Occasion.
- Weather suitability.
- Confidence score.
- “Why this works.”
- Actions: Wear This, Alternatives, Edit, Visualize.

Secondary modules:

- Alternative looks carousel.
- Wardrobe Score.
- Kyra’s Insight.
- Purchase opportunity with outfit unlock count.
- Upcoming occasions.
- Laundry/availability alert.
- Monthly progress.

Empty state:

- Prompt to add 5 closet items.

### 6.12 Outfit detail

- Full-height hero.
- Outfit name.
- Occasion tags.
- Weather range.
- Item strip.
- Why it works.
- Fit notes.
- Color story.
- Actions: Mark Worn, Schedule, Edit, Visualize, Share.
- Missing item CTA: “Complete this look.”

### 6.13 Outfit builder

Canvas center:

- Flat lay by default.
- Optional mannequin/avatar preview.

Category rail:

- Tops.
- Bottoms.
- Outerwear.
- Shoes.
- Watches.
- Accessories.
- Fragrance.

Behavior:

- Tap an item to replace.
- Long press to lock.
- Swipe category suggestions.
- Compatibility meter updates live.
- “Ask Kyra to finish” action.
- Save as outfit.

### 6.14 Closet overview

Header:

- My Closet.
- Search.
- Filter.
- Scan button.

Category tiles:

- Tops.
- Bottoms.
- Outerwear.
- Shoes.
- Accessories.
- Watches.
- Fragrance.
- All items.

Metrics:

- Total items.
- Estimated closet value.
- Average cost per wear.
- Most worn.
- Least worn.
- Versatility.

Views:

- Editorial grid.
- Compact list.
- Color spectrum.

Filters:

- Category.
- Color.
- Season.
- Brand.
- Condition.
- Fit.
- Availability.
- Wear frequency.

### 6.15 Item detail

Fields:

- Normalized cutout image.
- User photos.
- Name.
- Brand.
- Category and subtype.
- Color and secondary colors.
- Material.
- Pattern.
- Size.
- Fit.
- Condition.
- Purchase date.
- Price paid.
- Retailer.
- Product URL.
- Wear count.
- Last worn.
- Cost per wear.
- Outfit count.
- Seasonality.
- Care instructions.
- Laundry state.

Insights:

- Best pairings.
- Outfit gallery.
- Redundancy score.
- Replacement suggestion.

Actions:

- Mark worn.
- Add to laundry.
- Edit.
- Archive.
- Sell/donate later.

### 6.16 Scanner

Capture modes:

- Single item.
- Batch closet scan.
- Receipt/label.
- Full outfit mirror photo.

Camera guidance:

- Edge detection.
- Lighting indicator.
- Background quality.
- Blur warning.
- Auto capture optional.

Review screen:

- Segmented cutout.
- Suggested metadata.
- Confidence indicators.
- User correction.

### 6.17 Style Studio

Top controls:

- Outfit.
- Top.
- Bottom.
- Shoes.
- Accessories.
- Grooming future.

Main viewport:

- User avatar or reference image.
- Before/after compare.
- Generated-image label.

Prompt presets:

- Smart casual.
- Date night.
- Wedding.
- Vacation.
- Executive.
- Old-money inspired.
- Minimalist.
- Night out.

Advanced controls:

- Preserve face.
- Preserve body proportions.
- Preserve hair/facial hair.
- Background.
- Pose.
- Formality.
- Season.
- Color palette.

Generation states:

- Queued.
- Generating.
- Complete.
- Failed with retry.

Safety:

- Require user ownership/permission for personal images.
- Do not imply exact fit or body outcome.
- Provide deletion controls.

### 6.18 Shop the look

- Outfit preview.
- Owned items marked clearly.
- Missing items listed.
- Retailer, price, sizes, and affiliate disclosure.
- Add to wishlist.
- Open retailer.
- Find lower-cost alternative.
- Find higher-quality alternative.
- Secondhand option later.

### 6.19 Product decision page

Scores:

- Wardrobe compatibility.
- New outfits unlocked.
- Redundancy risk.
- Color fit.
- Lifestyle fit.
- Budget fit.
- Expected cost per wear.

Kyra verdict:

- Buy.
- Consider.
- Wait for sale.
- Skip.

### 6.20 Kyra conversation

Input:

- Text.
- Voice.
- Photo.
- Product link.
- Closet item.
- Outfit.

Suggested prompts:

- “What should I wear tonight?”
- “Does this fit correctly?”
- “Should I buy this?”
- “Build me a $500 capsule.”
- “Pack for a four-day trip.”

Responses can contain structured cards:

- Outfit cards.
- Product cards.
- Closet items.
- Comparison tables.
- Actions.

Conversation memory:

- Save durable preferences only when relevant.
- Allow users to inspect and delete style memories.

### 6.21 Discover

Sections:

- Kyra-curated lookbooks.
- Style education.
- Seasonal guides.
- Fit guides.
- Brand spotlights.
- Community inspiration future.

Do not make Discover a generic shopping feed.

### 6.22 Profile and stats

- Profile image.
- Style DNA.
- Wardrobe Score.
- Items owned.
- Outfits created.
- Cost per wear.
- Most worn colors.
- Monthly spend.
- Style Journey timeline.
- Subscription.
- Preferences.
- Privacy and data controls.

### 6.23 Monthly review

Kyra summarizes:

- New items.
- Spend.
- Wears.
- Best purchase.
- Underused items.
- Wardrobe versatility change.
- Next priority.
- One challenge for the next month.

### 6.24 Packing assistant

Inputs:

- Destination.
- Dates.
- Activities.
- Dress codes.
- Luggage constraints.
- Laundry access.

Outputs:

- Packing list.
- Daily outfit plan.
- Rewear map.
- Missing essentials.
- Weather contingencies.

---

## 7. FUNCTIONAL REQUIREMENTS

### Authentication

- Sign in with Apple.
- Email magic link or OTP.
- Session restoration.
- Account deletion inside app.

**Amended 2026-08-06 — ADR 0014.** "Guest migration to account" is removed
along with guest mode. Note that the migration this line required was never
fully built even while the feature existed: the shipped service migrated
closet items and no profile table, so a user who onboarded as a guest and
then signed in lost his onboarding answers — a data-loss bug ADR 0011's own
Consequences section had predicted.

### Permissions

Request only in context:

- Camera: when scanning.
- Photos: when importing.
- Location: when enabling weather.
- Calendar: when enabling occasion-aware recommendations.
- Notifications: after user sees value.
- Microphone: when using voice.

### Offline behavior

- Cached closet and outfits remain viewable.
- Local edits queue for sync.
- New scans can be captured and queued.
- Generative features require network.

### Notifications

- Daily outfit ready.
- Upcoming occasion.
- Laundry reminder.
- Price-drop future.
- Monthly review.
- Packing reminder.

Avoid excessive shopping notifications.

---

## 8. TECHNICAL ARCHITECTURE

### Recommended stack

#### iOS

- Swift 6.x.
- SwiftUI.
- Observation framework using `@Observable`.
- Structured concurrency with async/await.
- SwiftData for local cache and offline-first entities.
- AVFoundation for camera.
- Vision for segmentation, text recognition, and image analysis.
- PhotosUI for image import.
- StoreKit 2 for subscriptions.
- WeatherKit or server weather provider.
- EventKit for calendar integration.
- UserNotifications.
- AuthenticationServices for Sign in with Apple.

#### Backend

- Supabase Postgres.
- Supabase Auth.
- Supabase Storage.
- Supabase Realtime where useful.
- Supabase Edge Functions for protected orchestration.
- pgvector for embeddings.
- Row Level Security on every user-owned table.

#### AI/generative provider abstraction

Create a provider-neutral server interface. Do not hardcode the app directly to one model vendor.

Services:

- `StylistReasoningProvider`
- `VisionAnalysisProvider`
- `ImageGenerationProvider`
- `EmbeddingProvider`
- `ProductExtractionProvider`

The iOS client talks only to Astra Edge Functions.

### Architecture pattern

Feature-first modular architecture with clean boundaries:

```text
AstraStyle/
  App/
  Core/
    DesignSystem/
    Networking/
    Persistence/
    Auth/
    Analytics/
    Utilities/
  Features/
    Onboarding/
    Home/
    Closet/
    Scanner/
    Outfits/
    Studio/
    Kyra/
    Shopping/
    Discover/
    Profile/
    Subscription/
  Domain/
    Models/
    Repositories/
    Services/
  Resources/
  Tests/
```

Each feature contains:

```text
FeatureName/
  Views/
  ViewModels/
  Components/
  Models/
  Services/
  Routing/
  Tests/
```

### Dependency approach

Use protocol-based dependency injection with a root `AppContainer`. Avoid a heavy third-party DI framework.

Example protocols:

- `AuthRepository`
- `ClosetRepository`
- `OutfitRepository`
- `KyraRepository`
- `StudioRepository`
- `ShoppingRepository`
- `SubscriptionRepository`
- `WeatherService`
- `CalendarService`

### State management

- Local ephemeral UI state: `@State`.
- Feature-level observable state: `@Observable` view models.
- Shared authenticated session: injected session store.
- Persistent domain data: repositories backed by SwiftData and Supabase.
- Never place network calls directly in views.

---

## 9. DATA MODEL

Use UUID primary keys, `created_at`, `updated_at`, and soft deletion where appropriate.

### profiles

- `id`
- `display_name`
- `avatar_url`
- `location_name`
- `timezone`
- `units`
- `theme`
- `onboarding_completed_at`
- `subscription_tier`

### style_profiles

- `user_id`
- `primary_identity`
- `secondary_identities jsonb`
- `preferred_colors jsonb`
- `avoided_colors jsonb`
- `preferred_fit`
- `formality_preference`
- `logo_tolerance`
- `trend_tolerance`
- `accessory_preference`
- `style_summary`
- `embedding vector`

### body_profiles

- `user_id`
- `height_value`
- `weight_value`
- `chest`
- `waist`
- `inseam`
- `neck`
- `shoe_size`
- `shirt_size`
- `trouser_size`
- `fit_notes jsonb`

### lifestyle_profiles

- `user_id`
- `occupation_category`
- `dress_code`
- `common_occasions jsonb`
- `climate_preferences jsonb`
- `monthly_budget`
- `preferred_brands jsonb`
- `avoided_brands jsonb`
- `laundry_cadence`

### closet_items

- `id`
- `user_id`
- `name`
- `brand`
- `category`
- `subcategory`
- `primary_color`
- `secondary_colors jsonb`
- `pattern`
- `material jsonb`
- `size`
- `fit`
- `condition`
- `seasonality jsonb`
- `formality_score`
- `warmth_score`
- `water_resistance_score`
- `purchase_date`
- `price_paid`
- `currency`
- `retailer`
- `product_url`
- `wear_count`
- `last_worn_at`
- `laundry_state`
- `availability_state`
- `archived_at`
- `embedding vector`

### closet_item_images

- `id`
- `closet_item_id`
- `image_type`
- `storage_path`
- `background_removed_path`
- `is_primary`
- `analysis_metadata jsonb`

### outfits

- `id`
- `user_id`
- `name`
- `description`
- `occasion_tags jsonb`
- `weather_min`
- `weather_max`
- `formality_score`
- `compatibility_score`
- `source`
- `hero_image_url`
- `generated_preview_url`
- `is_favorite`
- `embedding vector`

### outfit_items

- `outfit_id`
- `closet_item_id nullable`
- `product_candidate_id nullable`
- `role`
- `sort_order`
- `is_required`

### outfit_wears

- `id`
- `outfit_id`
- `user_id`
- `worn_at`
- `occasion`
- `rating`
- `feedback`
- `weather_snapshot jsonb`

### style_feedback

- `id`
- `user_id`
- `target_type`
- `target_id`
- `signal`
- `reason_tags jsonb`
- `free_text`

Signals:

- like.
- dislike.
- wore.
- skipped.
- saved.
- purchased.
- returned.
- too_formal.
- too_casual.
- bad_fit.
- wrong_color.

### product_candidates

- `id`
- `canonical_url`
- `retailer`
- `brand`
- `name`
- `category`
- `price`
- `currency`
- `image_url`
- `affiliate_url`
- `availability jsonb`
- `attributes jsonb`
- `last_checked_at`

### user_product_evaluations

- `user_id`
- `product_candidate_id`
- `compatibility_score`
- `redundancy_score`
- `outfits_unlocked`
- `expected_cost_per_wear`
- `verdict`
- `reasoning`

### occasions

- `id`
- `user_id`
- `title`
- `starts_at`
- `ends_at`
- `location`
- `dress_code`
- `source`
- `calendar_event_identifier`

### daily_briefs

- `id`
- `user_id`
- `brief_date`
- `primary_outfit_id`
- `alternative_outfit_ids jsonb`
- `weather_snapshot jsonb`
- `schedule_snapshot jsonb`
- `kyra_message`

### kyra_threads

- `id`
- `user_id`
- `title`
- `last_message_at`

### kyra_messages

- `id`
- `thread_id`
- `role`
- `content`
- `structured_payload jsonb`
- `model_metadata jsonb`

### style_memories

- `id`
- `user_id`
- `memory_type`
- `content`
- `confidence`
- `source_message_id`
- `is_user_visible`
- `embedding vector`

### studio_generations

- `id`
- `user_id`
- `reference_image_path`
- `outfit_id`
- `prompt_payload jsonb`
- `status`
- `result_image_path`
- `provider`
- `error_message`

### subscriptions

- `user_id`
- `app_store_original_transaction_id`
- `product_id`
- `status`
- `expires_at`
- `environment`

### analytics_events

Prefer external analytics SDK or privacy-preserving first-party events; do not expose sensitive images or free-text prompts.

---

## 10. WARDROBE GRAPH

### Graph concepts

Nodes:

- User.
- Closet item.
- Outfit.
- Occasion.
- Style identity.
- Product candidate.
- Color.
- Season.
- Brand.
- Fit characteristic.

Edges:

- pairs_with.
- conflicts_with.
- worn_in.
- preferred_with.
- replaces.
- duplicates.
- unlocks.
- suited_for.
- owned_by.

### MVP implementation

Use relational tables plus computed compatibility, not a separate graph database.

Compatibility score 0–100:

```text
0.25 color compatibility
0.20 formality alignment
0.15 silhouette compatibility
0.10 season/weather suitability
0.10 user preference
0.10 historical co-wear/feedback
0.05 occasion relevance
0.05 availability/laundry
```

Weights should be configurable server-side.

### Purchase unlock count

To calculate “unlocks 18 outfits”:

1. Generate plausible combinations using owned items and the candidate.
2. Remove combinations below compatibility threshold.
3. Remove near-duplicates.
4. Count combinations that fill an existing wardrobe gap or pass quality threshold.
5. Cache the result.

### Wardrobe score

0–100 composite:

- Versatility 25%.
- Fit confidence 15%.
- Occasion coverage 15%.
- Color cohesion 10%.
- Wear utilization 15%.
- Condition 10%.
- Redundancy control 10%.

Do not equate expensive clothing with a higher score.

---

## 11. KYRA ORCHESTRATION

### System role

Kyra receives structured context rather than an unbounded dump of user data.

Context packet:

- User style profile.
- Relevant body/fit profile.
- Current weather.
- Relevant occasions.
- Available closet items.
- Recent feedback.
- Budget constraints.
- Durable memories.
- Requested task.

### Tool calls

Kyra can call server tools:

- `search_closet`
- `rank_outfits`
- `create_outfit`
- `analyze_product`
- `search_products`
- `get_weather`
- `get_schedule`
- `generate_studio_preview`
- `save_preference`
- `mark_item_worn`
- `create_packing_list`

### Response schema

```json
{
  "message": "string",
  "intent": "daily_outfit | product_advice | outfit_review | packing | education | general",
  "cards": [],
  "suggested_actions": [],
  "memory_proposals": [],
  "confidence": 0.0
}
```

### Guardrails

- Do not infer sensitive traits.
- Do not give medical body-change advice.
- Do not promise garment fit from imagery alone.
- Label visual generations as estimates.
- Clearly disclose affiliate relationships.
- Separate sponsored placement from organic ranking.

---

## 12. COMPUTER VISION PIPELINE

### Device-side

1. Detect blur and exposure.
2. Detect likely garment region.
3. Segment foreground where supported.
4. OCR label text.
5. Extract dominant colors.
6. Resize and compress.
7. Strip unnecessary metadata.
8. Upload signed object.

### Server-side

1. Classify category/subcategory.
2. Detect material/pattern cues.
3. Infer likely brand from label OCR, with confidence.
4. Generate normalized product title.
5. Estimate condition.
6. Produce searchable embedding.
7. Generate background-removed asset if device result is inadequate.

### User verification

All inferred fields remain editable. Low-confidence fields should be visibly marked.

---

## 13. STYLE STUDIO GENERATION PIPELINE

1. User selects a reference image.
2. Validate consent and content.
3. Generate a face/body identity representation through the chosen provider.
4. Build structured outfit prompt from exact garments.
5. Preserve proportions; do not beautify or alter body unless explicitly requested.
6. Generate 1 standard image for free/premium quota.
7. Store output with expiration or permanent-save choice.
8. Return generation metadata and disclaimer.

### Prompt template

```text
Create a realistic editorial menswear visualization using the provided authorized reference image. Preserve the person’s recognizable facial features, body proportions, skin tone, hair, and facial hair. Dress him in: [structured garment list]. Use [pose], [background], and [lighting]. The image is a visual styling estimate, not an exact representation of garment fit or color.
```

### Cost controls

- Queue jobs.
- Rate limit by tier.
- Cache repeated combinations.
- Use lower-cost draft generation before high-resolution export.
- Delete abandoned source images after configurable retention.

---

## 14. API / EDGE FUNCTIONS

Required endpoints:

- `POST /profile/complete-onboarding`
- `POST /style-dna/generate`
- `POST /closet/analyze-item`
- `POST /closet/batch-analyze`
- `POST /outfits/generate`
- `POST /outfits/rank`
- `POST /daily-brief/generate`
- `POST /kyra/respond`
- `POST /products/extract`
- `POST /products/evaluate`
- `POST /studio/generate`
- `GET /studio/status/:id`
- `POST /packing/generate`
- `POST /subscriptions/sync`
- `POST /app-store/webhook`
- `DELETE /account`

Every endpoint must:

- Validate JWT.
- Validate ownership.
- Validate request schema.
- Rate limit.
- Log request ID and latency.
- Avoid logging private images or full prompt contents.

---

## 15. SUPABASE SECURITY

### Row Level Security

Every user-owned table must enforce:

```sql
user_id = auth.uid()
```

Storage paths:

```text
users/{user_id}/closet/...
users/{user_id}/references/...
users/{user_id}/studio/...
```

Use signed URLs. Keep buckets private.

### Service role

Service-role keys exist only in Edge Functions. Never ship them in the app.

### Data deletion

Account deletion must remove:

- Database rows.
- Storage objects.
- Generated images.
- Embeddings.
- Style memories.
- Auth identity.

Use a deletion job with user-visible status if immediate deletion cannot complete synchronously.

---

## 16. SUBSCRIPTION MODEL

### Free

- Up to 30 closet items.
- Limited outfit generation.
- Basic Daily Brief.
- Three Kyra conversations per day.
- One Style Studio preview trial.

### Astra Style Premium

Target launch pricing for testing:

- $12.99/month.
- $79.99/year.

Premium:

- Unlimited closet.
- Full Daily Brief.
- Advanced Wardrobe Graph.
- Product verdicts.
- Packing assistant.
- Monthly reviews.
- Higher Style Studio quota.
- Advanced Kyra memory.

### Optional generation credits

Only add after subscription behavior is understood. Avoid a confusing launch economy.

### Paywall

- Marble hero.
- Clear benefit list.
- Monthly and annual plans.
- Restore purchases.
- Manage subscription.
- Legal links.

Use StoreKit 2 and server-side subscription reconciliation.

---

## 17. AFFILIATE COMMERCE

### Principles

- Recommendations rank for user value first.
- Sponsored products must be labeled.
- Affiliate availability must not change Kyra’s verdict.
- Retailer redirects open in `SFSafariViewController` or universal link.

### Product ingestion

MVP options:

1. Curated catalog maintained in admin.
2. Retailer affiliate feeds.
3. User-pasted product URLs analyzed on demand.

Do not rely on unrestricted scraping as the only product source.

---

## 18. ANALYTICS

Key events:

- onboarding_started/completed.
- closet_item_added.
- scan_corrected.
- outfit_generated.
- outfit_marked_worn.
- outfit_rejected.
- kyra_prompt_sent.
- product_evaluated.
- affiliate_link_opened.
- studio_generation_started/completed.
- paywall_viewed.
- subscription_started/renewed/cancelled.

North-star metrics:

- Weekly users who mark at least one outfit worn.
- Closet items added per activated user.
- Daily Brief acceptance rate.
- 30-day wardrobe engagement.
- Purchase recommendations that are saved vs skipped.
- Improvement in wardrobe utilization.

---

## 19. ACCESSIBILITY

- Full Dynamic Type support.
- VoiceOver labels for outfit imagery and controls.
- High-contrast alternative for champagne text.
- Do not encode meaning by color alone.
- Reduce Motion support.
- Minimum 44 pt controls.
- VoiceOver should read outfit item order logically.
- Generated images require editable alt descriptions.

---

## 20. PERFORMANCE TARGETS

- Cold launch to interactive: under 2.5 seconds on supported devices.
- Cached Home render: under 500 ms.
- Closet grid scrolling: 60 fps.
- Scanner shutter feedback: immediate.
- Item analysis: target under 8 seconds.
- Kyra first token/card: target under 2.5 seconds.
- Draft Studio generation: target under 30 seconds, with progress state.

Image handling:

- Thumbnails: HEIF/WebP equivalent where supported.
- Never render full-resolution originals in grids.
- Prefetch next outfit image.
- Use memory-aware caches.

---

## 21. ERROR AND EMPTY STATES

Every feature needs:

- Loading state.
- Skeleton state.
- Empty state.
- Offline state.
- Permission denied state.
- Recoverable error.
- Retry.

Examples:

- No closet items: “Add five pieces and Kyra can begin building real outfits.”
- Calendar denied: “You can still create occasions manually.”
- Studio failed: Preserve prompt and allow retry without consuming another credit when failure is provider-side.

---

## 22. TESTING REQUIREMENTS

### Unit tests

- Compatibility scoring.
- Wardrobe score.
- Cost-per-wear calculation.
- Subscription entitlement logic.
- Offline queue.
- Mapping API models to local models.
- Kyra structured response parsing.

### Integration tests

- Auth lifecycle.
- Closet upload and sync.
- Daily Brief generation.
- Product evaluation.
- Studio job polling.
- StoreKit sandbox purchase.

### UI tests

- Complete onboarding.
- Add a garment.
- Generate outfit.
- Mark worn.
- Ask Kyra.
- Open paywall and restore purchases.
- Delete account.

### Snapshot tests

- Major screens in light/dark mode.
- Dynamic Type sizes.
- Empty/loading/error states.

### Acceptance quality bar

- No placeholder lorem ipsum.
- No dead buttons.
- No hard-coded user name.
- No exposed API secrets.
- No unhandled network failure.
- No required permission requested before context.

---

## 23. MVP SCOPE

### Must ship

- Sign in with Apple and email.
- Full onboarding and Style DNA.
- Closet scan and manual editing.
- Closet grid and item detail.
- Outfit generation from owned clothing.
- Kyra chat with structured outfit cards.
- Daily Brief with weather.
- Outfit builder.
- Style Studio basic preview.
- Product-link analysis.
- Profile and Wardrobe Score.
- StoreKit subscription.
- Account deletion and privacy controls.

### Can follow shortly after

- Calendar integration.
- Packing assistant.
- Monthly review.
- Affiliate catalog.
- Batch closet scan.
- Watch widgets.
- Shareable lookbooks.

### Explicitly defer

- Public social network.
- Marketplace.
- Automated resale.
- Exact camera body measurements.
- Real-time AR try-on.
- Hairstyle and body transformation suite.
- Brand portal.

---

## 24. BUILD ORDER

### Phase 1 — Foundation

- Xcode project.
- Design tokens.
- Navigation shell.
- Supabase setup.
- Authentication.
- Local persistence.
- Networking and dependency container.

### Phase 2 — Identity

- Onboarding.
- Profile schemas.
- Style DNA generation.
- Home skeleton.

### Phase 3 — Closet

- Camera/import.
- Analysis Edge Function.
- Closet CRUD.
- Item detail.
- Offline sync.

### Phase 4 — Outfit intelligence

- Compatibility engine.
- Outfit generation.
- Outfit builder.
- Daily Brief.
- Wear feedback.

### Phase 5 — Kyra

- Conversation UI.
- Tool orchestration.
- Structured response cards.
- Memory controls.

### Phase 6 — Studio and commerce

- Reference capture.
- Generation queue.
- Results gallery.
- Product URL analysis.
- Affiliate redirects.

### Phase 7 — Monetization and hardening

- StoreKit.
- Paywall.
- Rate limits.
- Analytics.
- Accessibility.
- Testing.
- App Store assets.

---

## 25. CONFIGURATION AND SECRETS

Required environment variables in Edge Functions:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
STYLIST_PROVIDER_API_KEY
VISION_PROVIDER_API_KEY
IMAGE_PROVIDER_API_KEY
EMBEDDING_PROVIDER_API_KEY
WEATHER_PROVIDER_KEY_IF_USED
AFFILIATE_PROVIDER_KEYS
APP_STORE_SHARED_CONFIGURATION
```

The app receives only:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

Use `.xcconfig` files and CI secrets. Never commit production credentials.

---

## 26. SAMPLE DOMAIN TYPES

```swift
enum ClothingCategory: String, Codable, CaseIterable {
    case top, bottom, outerwear, shoes, accessory, watch, fragrance
}

enum LaundryState: String, Codable {
    case clean, wornOnce, laundry, unavailable
}

enum KyraVerdict: String, Codable {
    case buy, consider, waitForSale, skip
}

struct OutfitRecommendation: Identifiable, Codable {
    let id: UUID
    let name: String
    let reason: String
    let compatibilityScore: Int
    let itemIDs: [UUID]
    let missingProductIDs: [UUID]
}
```

---

## 27. SAMPLE ROOT APP STRUCTURE

```swift
@main
struct AstraStyleApp: App {
    @State private var appContainer = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appContainer)
                .preferredColorScheme(appContainer.settings.preferredColorScheme)
        }
    }
}
```

Root routing states:

```swift
enum AppRouteState {
    case launching
    case signedOut
    case onboarding
    case main
}
```

---

## 28. ADMIN REQUIREMENTS

Create a minimal web admin later for:

- Curated products.
- Editorial content.
- Style identities.
- Prompt versions.
- Compatibility weights.
- Feature flags.
- User support lookup.
- Generation failures.
- Affiliate disclosures.

Do not put admin credentials or functions in the iOS app.

---

## 29. LEGAL AND PRIVACY REQUIREMENTS

- Privacy policy describes image processing, model providers, retention, and affiliate relationships.
- Terms prohibit uploading images without permission.
- In-app account deletion.
- Export personal data.
- Delete individual reference and generated images.
- Clear generated-image disclaimer.
- App Tracking Transparency only if tracking is actually implemented.
- Avoid collecting unnecessary sensitive demographic data.
- Provide opt-out for model training; default should be no training on user images unless explicit consent is obtained.

---

## 30. DEFINITION OF DONE

The first production candidate is done when a new user can:

1. Install the app.
2. Sign in.
3. Complete onboarding.
4. Receive a coherent Style DNA.
5. Scan at least five garments.
6. Correct analysis metadata.
7. Receive three outfits made from owned items.
8. Ask Kyra what to wear for an occasion.
9. Mark an outfit worn.
10. Paste a retailer link and receive a buy/skip verdict.
11. Generate a visual styling estimate.
12. Subscribe and restore purchase.
13. View or delete stored style memories.
14. Delete the account and all associated data.

All of this must work in dark and light mode, with VoiceOver, under degraded network conditions, and without exposing provider credentials.

---

## 31. MASTER IMPLEMENTATION INSTRUCTION FOR CODING AGENTS

Build Astra Style as a production-quality native iOS app based strictly on this specification. Do not substitute a generic template, web wrapper, or mock-only prototype. Implement real navigation, persistent data models, repository abstractions, Supabase integration points, offline caching, error states, accessibility, and tests. Use mock services only where an external provider key is unavailable, and place each mock behind the same protocol as the production implementation. Every visible control must work. Use the supplied Astra assets and design tokens. Keep Kyra provider-neutral and return structured UI payloads rather than unparsed prose. Do not expose secrets in the client. Ensure the project builds without warnings and includes a README with setup, environment variables, Supabase migrations, Edge Function deployment, StoreKit configuration, and test instructions.

