# Retry
A retry algorithm for Swift Concurrency

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-concurrency-retry%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ph1ps/swift-concurrency-retry)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-concurrency-retry%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ph1ps/swift-concurrency-retry)

## Details

The library comes with two free functions, one with a generic clock and another one which uses the `ContinuousClock` as default.
```swift
public func retry<R, E, C>(
  maxAttempts: Int = 3,
  tolerance: C.Duration? = nil,
  clock: C,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  strategy: (E) -> RetryStrategy<C> = { _ in .backoff(.none) }
) async throws -> R where C: Clock, E: Error { ... }

public func retry<R, E>(
  maxAttempts: Int = 3,
  tolerance: ContinuousClock.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  strategy: (E) -> RetryStrategy<ContinuousClock> = { _ in .backoff(.none) }
) async throws -> R where E: Error { ... }
```

The `retry` function performs an asynchronous operation and retries it up to a specified number of attempts if it encounters an error. You can define a custom retry strategy based on the type of error encountered, and control the delay between attempts with a `BackoffStrategy`.

- Parameters:
  - `maxAttempts`: The maximum number of attempts to retry the operation. Defaults to 3.
  - `tolerance`: An optional tolerance for the delay duration to account for clock imprecision. Defaults to `nil`.
  - `isolation`: The inherited actor isolation.
  - `operation`: The asynchronous operation to perform. This function will retry the operation in case of error, based on the retry strategy provided.
  - `strategy`: A closure that determines the `RetryStrategy` for handling retries based on the error type. Defaults to `.backoff(.none)`, meaning no delay between retries.

- Returns: The result of the operation, if successful within the allowed number of attempts.
- Throws: Rethrows the last encountered error if all retry attempts fail or if the retry strategy specifies stopping retries or any error thrown by `clock`
- Precondition: `maxAttempts` must be greater than 0.

### Backoff
This library ships with 6 prebuilt backoff strategies:

#### None
A backoff strategy with no delay between attempts.

This strategy enforces a zero-duration delay, making retries immediate. It’s suitable for situations where retries should happen as soon as possible without any waiting period.

$`f(x) = 0`$ where `x` is the current attempt.
```swift
extension BackoffStrategy {
  public static var none: Self { ... }
}
```

#### Constant
A backoff strategy with a constant delay between each attempt.

This strategy applies a fixed, unchanging delay between retries, regardless of attempt count. It’s ideal for retry patterns where uniform intervals between attempts are desired.

$`f(x) = c`$ where `x` is the current attempt.
```swift
extension BackoffStrategy {
  public static func constant(c: C.Duration) -> Self { ... }
}
```

#### Linear
A backoff strategy with a linearly increasing delay between attempts.

This strategy gradually increases the delay after each retry, beginning with an initial delay and scaling linearly. Useful for scenarios where delays need to increase consistently over time.

$`f(x) = ax + b`$ where `x` is the current attempt.
```swift
extension BackoffStrategy {
  public static func linear(a: C.Duration, b: C.Duration) -> Self { ... }
}
```

#### Exponential
A backoff strategy with an exponentially increasing delay between attempts.

This strategy grows the delay exponentially, starting with an initial duration and applying a multiplicative factor after each retry. Suitable for cases where retries should become increasingly sparse.

$`f(x) = a * b^x`$ where `x` is the current attempt.

```swift
extension BackoffStrategy {
  public static func exponential(a: C.Duration, b: Int) -> Self { ... }
}
```

#### Maximum
Limits the maximum delay duration for this backoff strategy.

This method ensures the backoff delay does not exceed the defined maximum duration, helping to avoid overly long wait times between retries. This retains the original backoff pattern up to the specified cap.

$`g(x) = min(f(x), M)`$ where `x` is the current attempt and `f(x)` the base backoff strategy.
```swift
extension BackoffStrategy {
  public func max(_ M: C.Duration) -> Self { ... }
}
```

#### Jitter
Applies jitter to the delay duration, introducing randomness into the backoff interval.

This method randomizes the delay for each retry attempt within a range from zero up to the base duration. Jitter can help reduce contention when multiple sources retry concurrently in distributed systems.

$`g(x) = random[0, f(x)[`$ where `x` is the current attempt and `f(x)` the base backoff strategy.
```swift
@available(iOS 18.0, macOS 15.0, macCatalyst 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
extension BackoffStrategy where C.Duration == Duration {
  public func jitter<T>(using generator: T = SystemRandomNumberGenerator()) -> Self where T: RandomNumberGenerator { ... }
}
```

## Examples
To fully understand this, let's illustrate 3 customizations of this function with `URLSession.shared.data(from: url)` as example operation:

### Customization 1
Use the defaults:
```swift
let (data, response) = try await retry {
  try await URLSession.shared.data(from: url)
}
```
If the operation succeeds, the result is returned immediately.
However if any error occurs, the operation will be tried 2 more times, as the default maximum attempts are 3.
Between the consecutive attempts, there will be no delay, as, again, the default retry strategy is to not add any backoff.

### Customization 2
Use a custom backoff strategy and custom amount of attempts:
```swift
let (data, response) = try await retry(maxAttempts: 5) {
  try await URLSession.shared.data(from: url)
} strategy: { _ in
  return .backoff(.constant(c: .seconds(2)))
}
```
Similarly to the first customization, if any error occurs, the operation will be tried 4 more times.
However, between consecutive attempts, it will wait for 2 seconds until it will run operation again.

### Customization 3
Use a custom backoff and retry strategy:
```swift
struct TooManyRequests: Error {
  let retryAfter: Double
}

let (data, response) = try await retry {
  let (data, response) = try await URLSession.shared.data(from: url)

  if
    let response = response as? HTTPURLResponse,
    let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init),
    response.statusCode == 429
  {
    throw TooManyRequests(retryAfter: retryAfter)
  }

  return (data, response)
} strategy: { error in
  if let error = error as? TooManyRequests {
    return .backoff(.constant(c: .seconds(error.retryAfter)))
  } else {
    return .stop
  }
}
```
A common behavior for servers is to return an HTTP status code 429 with a recommended backoff if the load gets too high.
Contrary to the first two examples, we only retry if the error is of type `TooManyRequests`, any other errors will be rethrown and retrying is stopped.
The constant backoff is dynamically fetched from the custom error and passed as seconds.

## Improvements
- Only have one free function with a default expression of `ContinuousClock` for the `clock` parameter.
  - Blocked by: https://github.com/swiftlang/swift/issues/72199
