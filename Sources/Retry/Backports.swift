#if swift(<6.0)
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
///   return .backoff(.constant(c: .seconds(2)))
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
///     return .backoff(.constant(c: .seconds(error.retryAfter)))
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
///   - operation: The asynchronous operation to perform. This function will retry the operation in case of error, based on the retry strategy provided.
///   - strategy: A closure that determines the `RetryStrategy` for handling retries based on the error type. Defaults to `.backoff(.none)`, meaning no delay between retries.
///
/// - Returns: The result of the operation, if successful within the allowed number of attempts.
/// - Throws: Rethrows the last encountered error if all retry attempts fail or if the retry strategy specifies stopping retries or any error thrown by `clock`
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, C>(
  maxAttempts: Int = 3,
  tolerance: C.Duration? = nil,
  clock: C,
  operation: () async throws -> R,
  strategy: (Error) -> RetryStrategy<C> = { _ in .backoff(.none) }
) async throws -> R where C: Clock, R: Sendable {
  
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
///   return .backoff(.constant(c: .seconds(2)))
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
///     return .backoff(.constant(c: .seconds(error.retryAfter)))
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
///   - operation: The asynchronous operation to perform. This function will retry the operation in case of error, based on the retry strategy provided.
///   - strategy: A closure that determines the `RetryStrategy` for handling retries based on the error type. Defaults to `.backoff(.none)`, meaning no delay between retries.
///
/// - Returns: The result of the operation, if successful within the allowed number of attempts.
/// - Throws: Rethrows the last encountered error if all retry attempts fail or if the retry strategy specifies stopping retries or any error thrown by `ContinuousClock`
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R>(
  maxAttempts: Int = 3,
  tolerance: ContinuousClock.Duration? = nil,
  operation: () async throws -> R,
  strategy: (Error) -> RetryStrategy<ContinuousClock> = { _ in .backoff(.none) }
) async throws -> R where R: Sendable {
  try await retry(maxAttempts: maxAttempts, tolerance: tolerance, clock: ContinuousClock(), operation: operation, strategy: strategy)
}
#endif

#if swift(<5.9)
extension Task where Success == Never, Failure == Never {
  static func sleep<C: Clock>(
    for duration: C.Instant.Duration,
    tolerance: C.Instant.Duration? = nil,
    clock: C = ContinuousClock()
  ) async throws {
    try await clock.sleep(for: duration, tolerance: tolerance)
  }
}

extension Clock {
  func sleep(
    for duration: Instant.Duration,
    tolerance: Instant.Duration? = nil
  ) async throws {
    try await sleep(until: now.advanced(by: duration), tolerance: tolerance)
  }
}
#endif
