# ``Understudy``

Mocks and fakes for your Swift tests, written for you.

## Overview

Understudy writes test doubles: stand-ins a test uses in place of a real dependency, such as a network client, a database or a clock, so the test decides what the dependency answers and can check how it was called. Mark the functions and properties your double stands in for, and the ``GenerateSpies()`` macro writes a spy for each one, which records every call and answers the way your test says.

New to Understudy? Start with the tutorial, which writes a first double and a test for it in about ten minutes. Each guide below answers one question with a worked example. The [README](https://github.com/joeoct-oss/Understudy#readme) is the one home of every rule, and each page links to the part it relies on.

The test clock is here too: ``TestClock`` moves only when your test moves it. `@Sample`, which writes complete sample values for structs, is in its own product, `UnderstudySamples`.

## Topics

### Essentials

- <doc:/tutorials/Understudy>

### Guides

- <doc:TestCodeThatWaits>
- <doc:CheckCallsAcrossDoubles>
- <doc:GiveEachTestItsOwnStaticSpies>
- <doc:CheckThatAMockWasUsed>
- <doc:DoubleAProtocolThatDeclaresAnInitializer>

### Writing doubles

- ``GenerateSpies()``
- ``Spied()``
- ``SpiedProperty()``
- ``Recorded``

### Spies

- ``Spy``
- ``ThrowingSpy``
- ``PropertySpy``

### Waiting for calls and time

- ``HeldCall``
- ``TestClock``

### Checking calls

- ``CallOrder``
- ``Watched``
- ``CallOrderBuilder``
- ``VerificationLocation``

### Test traits

- ``VerifiesMocks``
- ``FreshSpies``
- ``StaticSpies``
