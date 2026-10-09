# P6-SHOP-06 Shop the Look acceptance

Both Shop the Look simulator tests passed on October 9, 2026: 2 cases, zero
failures, 68.771 seconds. Log: `/tmp/astra-shopping-ax-ui-verification-2.log`.
The combined run failed its separate accessibility cases; this document claims
only the successful Shop the Look suite.

The candidate-backed case verifies visibly separate owned/missing sections,
an outfit preview, a persisted explicit product candidate, retailer, price,
available sizes, sponsorship and affiliate disclosure, and navigation to Product
Decision. It uses a deterministic mock-only saved outfit and synthetic product;
no retailer or provider is called.

The closet-only case verifies real owned pieces and the honest explanation that
no researched products are attached, with a separate catalog action. The app
does not infer purchasable items from the category of an owned garment.

Native unit tests cover owner checks, candidate relationships, and missing-data
behavior. The earlier complete native unit run passed 1,092 Swift Testing tests
plus 33 XCTest cases. Adjacent higher-quality alternative ranking remains
separate P6-SHOP-05 work; compatibility is not presented as product quality.
