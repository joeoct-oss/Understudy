# Check calls across doubles

Check the order in which your code called several doubles, such as saving before sending.

## Overview

Each spy keeps its own calls in order. When the order across spies matters, watch them with one ``CallOrder``, giving each a name:

```swift
let order = CallOrder {
    Watched(store.saveSpy, as: "save")
    Watched(sync.sendSpy, as: "send")
}

checkout.complete()

let expectedOrder = ["save", "send"]
#expect(order.names == expectedOrder)
```

`order.names` holds one name per call, so a spy called twice shows twice. The order sees only calls made after it starts watching, and `order.watch(_:as:)` adds a spy later, such as one made in the middle of the test.

Check the order only when it is the behaviour: a checkout that must save before it sends. When either order is fine, check each spy's calls instead, so the test doesn't break when the code changes an order nobody relies on.

## Where the rules live

- [Call order](https://github.com/joeoct-oss/Understudy#call-order) in the README.
