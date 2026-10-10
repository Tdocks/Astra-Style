# Subscription tests

This directory records test ownership for the Subscription feature. Executable test sources remain in the shared `ios/AstraStyle/Tests/UnitTests` and `UITests` targets so XcodeGen continues using the existing targets and shared support.

Current related test sources:

- [`PaywallViewModelTests.swift`](../../../Tests/UnitTests/PaywallViewModelTests.swift)
- [`ReferralCopyTests.swift`](../../../Tests/UnitTests/ReferralCopyTests.swift)
- [`SubscriptionEntitlementTests.swift`](../../../Tests/UnitTests/SubscriptionEntitlementTests.swift)

Add new tests to the existing target and update this index. `project.yml` excludes the feature documentation from the application bundle.
