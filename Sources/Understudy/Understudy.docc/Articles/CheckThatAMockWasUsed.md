# Check that a mock was used

Say which calls a double must get, and have the test fail when they don't happen, or when a call nobody expected does.

## Overview

A spy is lenient: it records calls and answers, and the test reads what it needs. Give a spy an expectation and it becomes a strict mock, which `verify()` checks:

```swift
analytics.trackSpy.expect("checkout")
analytics.trackSpy.expect(times: 2) { $0.hasPrefix("view") }

checkout.complete()

analytics.trackSpy.verify()
```

`verify()` reports every expected call that didn't happen and every call nobody expected, as Swift Testing issues at the test's line. `expectNoCalls()` makes any call a failure.

### Verify at the end of every test

With `.verifiesMocks` on a test or a suite, every spy given an expectation is checked when the test ends, so a forgotten `verify()` can't pass silently. An unmet expectation is reported at its `expect` line:

```swift
@Test(.verifiesMocks)
func payingSendsOnePaymentEvent() {
    analytics.trackSpy.expect("paid")

    payment.confirm()
}
```

A spy with no expectations is never checked, so lenient stays the default.

### When to use a mock

Check state first: what the screen shows, what the store holds. Keep a mock for an effect the user relies on that leaves no state to read, such as an event sent or a message posted.

## Where the rules live

- [Strict mocks](https://github.com/joeoct-oss/Understudy#strict-mocks) in the README, with what `.verifiesMocks` covers and its limits.
- ``VerifiesMocks``.
