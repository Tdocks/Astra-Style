# Shopping tests

This directory records test ownership for the Shopping feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`LiveShoppingPurchasePaginationTests.swift`](../../../Tests/UnitTests/LiveShoppingPurchasePaginationTests.swift)
- [`LiveShoppingWishlistPaginationTests.swift`](../../../Tests/UnitTests/LiveShoppingWishlistPaginationTests.swift)
- [`ProductAlternativeTests.swift`](../../../Tests/UnitTests/ProductAlternativeTests.swift)
- [`ProductDecisionCopyTests.swift`](../../../Tests/UnitTests/ProductDecisionCopyTests.swift)
- [`ProductDecisionViewModelTests.swift`](../../../Tests/UnitTests/ProductDecisionViewModelTests.swift)
- [`ProductLinkFlowUITests.swift`](../../../Tests/UITests/ProductLinkFlowUITests.swift)
- [`ReceiptSuggestionsTests.swift`](../../../Tests/UnitTests/ReceiptSuggestionsTests.swift)
- [`ShopTheLookUITests.swift`](../../../Tests/UITests/ShopTheLookUITests.swift)
- [`ShopTheLookViewModelTests.swift`](../../../Tests/UnitTests/ShopTheLookViewModelTests.swift)
- [`ShopViewModelTests.swift`](../../../Tests/UnitTests/ShopViewModelTests.swift)
- [`ShoppingEvaluationCacheTests.swift`](../../../Tests/UnitTests/ShoppingEvaluationCacheTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
