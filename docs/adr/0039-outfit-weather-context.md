# ADR 0039 — Structured weather for closet recommendations

Date: 2026-10-09
Status: Accepted; implementation awaiting native and hosted verification

## Decision

Outfit generation accepts an optional weather_context containing current temperature in Celsius, precipitation probability, the provider observation timestamp, and optional season. The iOS app obtains these values from WeatherKit only when weather permission is already authorized. It sends neither coordinates nor location names. It does not infer a current observation from daily high/low temperatures or replace the observation timestamp with request time.

The client omits incomplete, nonfinite, out-of-range, or stale snapshots. The server independently validates supplied values: temperature -90 through 65 Celsius, precipitation 0 through 1, observation age at most two hours, and future clock skew at most five minutes. Invalid supplied context returns validation failure; absent context retains the scorer’s documented missing-weather prior. Existing clients remain compatible.

Weather is preference context, not an authorization or entitlement input. Explicit owned occasion dress codes remain authoritative for formality; weather influences the existing weather score without changing compatibility weights. Natural-language forecast prose is not parsed into structured weather.

## Verification

Required evidence includes legacy snapshot decoding, wire units and timestamp encoding, absence of location data, denied/unrequested permission behavior, stale/future omission, independent server validation, and scoring-context propagation. Simulator tests cannot establish actual location permission behavior or WeatherKit availability on a user device. Those checks remain device acceptance gates.
