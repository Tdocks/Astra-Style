# ADR 0046 — Discover editorial guides alongside personal looks

Date: 2026-10-09
Status: Accepted

## Context

The user requested implementing the remaining master-plan features, including the unfinished Discover education surface. The earlier launch cut postponed guides and brand pages. This decision restores those features while preserving Discover’s existing personal-look ordering and public-sharing privacy controls.

## Decision

Keep saved looks, opt-in public worn looks, and evaluated wardrobe-gap Unlocks first. Append style, seasonal, fit, and brand education from a versioned bundled JSON configuration. The repository validates publication state, identifiers, ordering, source links, and commercial disclosures before displaying content. Detail routes render actual articles.

Initial content comprises eight original guides. Brand field notes link primary brand sources and identify themselves as independent, unpaid editorial. Any sponsored content requires a visible disclosure on both card and detail. Articles do not introduce affiliate purchase buttons or claim an endorsement.

Bundled configuration is the first editorial publishing mechanism; a remotely editable CMS is not implied. Updating bundled articles requires a new app build.

## Verification

Repository and detail-model tests cover configuration validation and disclosures. Simulator tests exercise all four article categories. Completion of those checks is required before closing the implementation ticket.
