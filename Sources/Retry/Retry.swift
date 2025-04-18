import _PowShims

/// A generic strategy for implementing a backoff mechanism.
///
/// `BackoffStrategy` defines how to calculate a delay duration based on the number of retry attempts.
/// This can be useful for implementing retry policies with increasing delays between attempts.
public struct BackoffStrategy<C> where C: Clock {
  public let duration: (Int) -> C.Duration
  public init(duration: @escaping (_ attempt: Int) -> C.Duration) { self.duration = duration }
}

extension BackoffStrategy {
  /// A backoff strategy with no delay between attempts.
  ///
  /// This strategy enforces a zero-duration delay, making retries immediate. It’s suitable for situations
  /// where retries should happen as soon as possible without any waiting period.
  /// - Note: `f(x) = 0` where `x` is the current attempt.
  public static var none: Self {
    .init { _ in .zero }
  }
  
  /// A backoff strategy with a constant delay between each attempt.
  ///
  /// This strategy applies a fixed, unchanging delay between retries, regardless of attempt count. It’s ideal
  /// for retry patterns where uniform intervals between attempts are desired.
  /// - Parameter c: The constant duration to wait between each retry attempt.
  /// - Note: `f(x) = c` where `x` is the current attempt.
  public static func constant(_ c: C.Duration) -> Self {
    .init { _ in c }
  }
  
  /// A backoff strategy with a linearly increasing delay between attempts.
  ///
  /// This strategy gradually increases the delay after each retry, beginning with an initial delay and scaling
  /// linearly. Useful for scenarios where delays need to increase consistently over time.
  /// - Parameters:
  ///   - a: The incremental delay increase applied with each retry attempt.
  ///   - b: The base delay duration added to each retry.
  /// - Note: `f(x) = ax + b` where `x` is the current attempt.
  public static func linear(a: C.Duration, b: C.Duration) -> Self {
    .init { attempt in a * attempt + b }
  }
  
  /// A backoff strategy with an exponentially increasing delay between attempts.
  ///
  /// This strategy grows the delay exponentially, starting with an initial duration and applying a multiplicative
  /// factor after each retry. Suitable for cases where retries should become increasingly sparse.
  /// - Parameters:
  ///   - a: The base delay duration applied before any retry attempt.
  ///   - b: The growth factor applied at each retry attempt.
  /// - Note: `f(x) = a * b^x` where `x` is the current attempt.
  public static func exponential(a: C.Duration, b: Double) -> Self where C.Duration == Duration {
    .init { attempt in a * pow(b, Double(attempt)) }
  }
  
  /// Enforces a minimum delay duration for this backoff strategy.
  ///
  /// This method ensures the backoff delay is never shorter than the defined minimum duration, helping to
  /// maintain a baseline wait time between retries. This retains the original backoff pattern but raises
  /// durations below the specified threshold to the minimum value.
  /// - Parameter m: The minimum allowable duration for each retry attempt.
  /// - Note: `g(x) = max(f(x), m)` where `x` is the current attempt and `f(x)` the base backoff strategy.
  public func min(_ m: C.Duration) -> Self {
    .init { attempt in Swift.max(duration(attempt), m) }
  }
  
  /// Limits the maximum delay duration for this backoff strategy.
  ///
  /// This method ensures the backoff delay does not exceed the defined maximum duration, helping to avoid
  /// overly long wait times between retries. This retains the original backoff pattern up to the specified cap.
  /// - Parameter M: The maximum allowable duration for each retry attempt.
  /// - Note: `g(x) = min(f(x), M)` where `x` is the current attempt and `f(x)` the base backoff strategy.
  public func max(_ M: C.Duration) -> Self {
    .init { attempt in Swift.min(duration(attempt), M) }
  }
  
  /// Applies jitter to the delay duration, introducing randomness into the backoff interval.
  ///
  /// This method randomizes the delay for each retry attempt within a range from zero up to the base duration.
  /// Jitter can help reduce contention when multiple sources retry concurrently in distributed systems.
  /// - Parameter generator: A custom random number generator conforming to the `RandomNumberGenerator` protocol. Defaults to `SystemRandomNumberGenerator`.
  /// - Note: `g(x) = random[0, f(x)[` where `x` is the current attempt and `f(x)` the base backoff strategy.
  @available(iOS 18.0, macOS 15.0, macCatalyst 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
  public func jitter<T>(using generator: T = SystemRandomNumberGenerator()) -> Self where T: RandomNumberGenerator, C.Duration == Duration {
    var generator = generator
    let attosecondsPerSecond: Int128 = 1_000_000_000_000_000_000
    return .init { attempt in
      let duration = duration(attempt)
      let (seconds, attoseconds) = Int128.random(
        in: 0..<(Int128(duration.components.seconds) * attosecondsPerSecond + Int128(duration.components.attoseconds)),
        using: &generator
      ).quotientAndRemainder(dividingBy: attosecondsPerSecond)
      return .init(secondsComponent: Int64(seconds), attosecondsComponent: Int64(attoseconds))
    }
  }
}

/// A strategy for managing retry attempts, with options for either backoff-based retries or immediate termination.
///
/// `RetryStrategy` allows you to define a retry policy that can either use a customizable backoff strategy
/// to manage retry timing, or stop retrying entirely after a given point.
public enum RetryStrategy<C> where C: Clock {
  case backoff(BackoffStrategy<C>)
  case stop
}

/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// The `retry` function performs an asynchronous operation and retries it up to a specified number of attempts
/// if it encounters an error. You can define a custom retry strategy based on the type of error encountered,
/// and control the delay between attempts with a `BackoffStrategy`.
///
/// ## Examples
/// To fully understand this, let's illustrate the 3 customizations of this function with `URLSession.shared.data(from: url)` as example operation:
///
/// ### Customization 1
/// Use the defaults:
/// ```swift
/// let (data, response) = try await retry {
///   try await URLSession.shared.data(from: url)
/// }
/// ```
/// If the operation succeeds, the result is returned immediately.
/// However if any error occurs, the operation will be tried 2 more times, as the default maximum attempts are 3.
/// Between the consecutive attempts, there will be no delay, as, again, the default retry strategy is to not add any backoff.
///
/// ### Customization 2
/// Use a custom backoff strategy and custom amount of attempts:
/// ```swift
/// let (data, response) = try await retry(maxAttempts: 5) {
///   try await URLSession.shared.data(from: url)
/// } strategy: { _ in
///   return .backoff(.constant(.seconds(2)))
/// }
/// ```
/// Similarly to the first customization, if any error occurs, the operation will be tried 4 more times.
/// However, between consecutive attempts, it will wait for 2 seconds until it will run operation again.
///
/// ### Customization 3
/// Use a custom backoff and retry strategy:
/// ```swift
/// struct TooManyRequests: Error {
///   let retryAfter: Double
/// }
///
/// let (data, response) = try await retry {
///   let (data, response) = try await URLSession.shared.data(from: url)
///
///   if
///     let response = response as? HTTPURLResponse,
///     let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init),
///     response.statusCode == 429
///   {
///     throw TooManyRequests(retryAfter: retryAfter)
///   }
///
///   return (data, response)
/// } strategy: { error in
///   if let error = error as? TooManyRequests {
///     return .backoff(.constant(.seconds(error.retryAfter)))
///   } else {
///     return .stop
///   }
/// }
/// ```
/// A common behavior for servers is to return an HTTP status code 429 with a recommended backoff if the load gets too high.
/// Contrary to the first two examples, we only retry if the error is of type `TooManyRequests`, any other errors will be rethrown and retrying is stopped.
/// The constant backoff is dynamically fetched from the custom error and passed as seconds.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to `nil`.
///   - clock: The clock used to wait for delays between retries.
///   - isolation: The inherited actor isolation.
///   - operation: The asynchronous operation to perform. This function will retry the operation in case of error, based on the retry strategy provided.
///   - strategy: A closure that determines the `RetryStrategy` for handling retries based on the error type. Defaults to `.backoff(.none)`, meaning no delay between retries.
///
/// - Returns: The result of the operation, if successful within the allowed number of attempts.
/// - Throws: Rethrows the last encountered error if all retry attempts fail or if the retry strategy specifies stopping retries or any error thrown by `clock`
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E, C>(
  maxAttempts: Int = 3,
  tolerance: C.Duration? = nil,
  clock: C,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  strategy: (E) -> RetryStrategy<C> = { _ in .backoff(.none) }
) async throws -> R where C: Clock, E: Error {
  
  precondition(maxAttempts > 0, "Retry must have at least one attempt")
  
  for attempt in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch where Task.isCancelled {
      throw error
    } catch {
      switch strategy(error) {
      case .backoff(let strategy):
        try await Task.sleep(for: strategy.duration(attempt), tolerance: tolerance, clock: clock)
      case .stop:
        throw error
      }
    }
  }
  
  return try await operation()
}

/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// The `retry` function performs an asynchronous operation and retries it up to a specified number of attempts
/// if it encounters an error. You can define a custom retry strategy based on the type of error encountered,
/// and control the delay between attempts with a `BackoffStrategy`. `ContinuousClock` will be used as the default clock.
///
/// ## Examples
/// To fully understand this, let's illustrate the 3 customizations of this function with `URLSession.shared.data(from: url)` as example operation:
///
/// ### Customization 1
/// Use the defaults:
/// ```swift
/// let (data, response) = try await retry {
///   try await URLSession.shared.data(from: url)
/// }
/// ```
/// If the operation succeeds, the result is returned immediately.
/// However if any error occurs, the operation will be tried 2 more times, as the default maximum attempts are 3.
/// Between the consecutive attempts, there will be no delay, as, again, the default retry strategy is to not add any backoff.
///
/// ### Customization 2
/// Use a custom backoff strategy and custom amount of attempts:
/// ```swift
/// let (data, response) = try await retry(maxAttempts: 5) {
///   try await URLSession.shared.data(from: url)
/// } strategy: { _ in
///   return .backoff(.constant(.seconds(2)))
/// }
/// ```
/// Similarly to the first customization, if any error occurs, the operation will be tried 4 more times.
/// However, between consecutive attempts, it will wait for 2 seconds until it will run operation again.
///
/// ### Customization 3
/// Use a custom backoff and retry strategy:
/// ```swift
/// struct TooManyRequests: Error {
///   let retryAfter: Double
/// }
///
/// let (data, response) = try await retry {
///   let (data, response) = try await URLSession.shared.data(from: url)
///
///   if
///     let response = response as? HTTPURLResponse,
///     let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init),
///     response.statusCode == 429
///   {
///     throw TooManyRequests(retryAfter: retryAfter)
///   }
///
///   return (data, response)
/// } strategy: { error in
///   if let error = error as? TooManyRequests {
///     return .backoff(.constant(.seconds(error.retryAfter)))
///   } else {
///     return .stop
///   }
/// }
/// ```
/// A common behavior for servers is to return an HTTP status code 429 with a recommended backoff if the load gets too high.
/// Contrary to the first two examples, we only retry if the error is of type `TooManyRequests`, any other errors will be rethrown and retrying is stopped.
/// The constant backoff is dynamically fetched from the custom error and passed as seconds.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to `nil`.
///   - isolation: The inherited actor isolation.
///   - operation: The asynchronous operation to perform. This function will retry the operation in case of error, based on the retry strategy provided.
///   - strategy: A closure that determines the `RetryStrategy` for handling retries based on the error type. Defaults to `.backoff(.none)`, meaning no delay between retries.
///
/// - Returns: The result of the operation, if successful within the allowed number of attempts.
/// - Throws: Rethrows the last encountered error if all retry attempts fail or if the retry strategy specifies stopping retries or any error thrown by `ContinuousClock`
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E>(
  maxAttempts: Int = 3,
  tolerance: ContinuousClock.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  strategy: (E) -> RetryStrategy<ContinuousClock> = { _ in .backoff(.none) }
) async throws -> R where E: Error {
  try await retry(maxAttempts: maxAttempts, tolerance: tolerance, clock: ContinuousClock(), operation: operation, strategy: strategy)
}
