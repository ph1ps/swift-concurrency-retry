/// A generic strategy for implementing a backoff mechanism.
///
/// `BackoffStrategy` defines how to calculate a delay duration based on the
/// number of retry attempts and the error encountered. This can be useful for
/// implementing retry policies with increasing delays between attempts.
public struct BackoffStrategy<C, E> where C: Clock, E: Error {
  let duration: (Int, E) -> C.Duration
  public init(duration: @escaping (Int, E) -> C.Duration) {
    self.duration = duration
  }
}

extension BackoffStrategy {
  /// Creates a `BackoffStrategy` with no delay between retry attempts.
  ///
  /// This strategy always returns a zero duration, meaning that there will be no wait
  /// time between retries. This can be useful when you want to retry immediately without any
  /// backoff mechanism.
  /// - Note: `f(x) = 0` where `x` is the current attempt.
  public static func none() -> Self { .init { _, _ in .zero } }
  
  /// Creates a `BackoffStrategy` with a constant delay duration between retry attempts.
  ///
  /// This strategy uses a fixed delay for all retry attempts, regardless of the retry count
  /// or the error encountered. It’s useful when a consistent wait time is desired between retries.
  ///
  /// - Parameter c: The constant delay duration to apply between retries.
  /// - Note: `f(x) = c` where `x` is the current attempt.
  public static func constant(c: C.Duration) -> Self { .init { _, _ in c } }
  
  /// Creates a `BackoffStrategy` with a linearly increasing delay duration between retry attempts.
  ///
  /// This strategy calculates the delay as a linear function of the retry attempt count.
  /// This means the delay increases proportionally with each retry attempt, allowing for a gradual backoff.
  ///
  /// - Parameters:
  ///   - a: The multiplier for the retry attempt count, controlling the growth rate of the delay.
  ///   - b: The base duration added to each calculated delay, setting an initial delay.
  /// - Note: `f(x) = ax + b` where `x` is the current attempt.
  public static func linear(a: C.Duration, b: C.Duration) -> Self { .init { attempt, _ in a * attempt + b } }
}

extension BackoffStrategy {
  /// Returns a new `BackoffStrategy` that caps the delay duration at a maximum value.
  ///
  /// This strategy limits the delay duration by applying an upper bound `M`. For each retry attempt,
  /// the delay will be the minimum of the computed duration from the original strategy and `M`.
  /// This ensures that the delay never exceeds the specified maximum.
  ///
  /// - Parameter M: The maximum allowable duration for any retry delay.
  /// - Note: `g(x) = min(f(x), M)` where `x` is the current attempt and `f(x)` the base backoff strategy.
  public func max(_ M: C.Duration) -> Self { .init { attempt, error in min(duration(attempt, error), M) } }
}

#if swift(>=6.0)
/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// This function attempts to run the given `operation` a specified number of times (`maxAttempts`) in case of failure.
/// After each failed attempt that matches the specified error condition, it waits for a duration calculated
/// by the provided backoff strategy. This allows for a customizable retry policy with support for error matching,
/// delay between attempts, and clock tolerance.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - backoffStrategy: The strategy used to determine the delay between retry attempts. Defaults to `.none()`, meaning no delay.
///   - clock: The clock used to wait for delays between retries.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to nil.
///   - isolation: The inherited actor isolation.
///   - operation: The asynchronous operation to perform, which may throw an error.
///   - matchesError: A closure that determines if an error thrown by `operation` should trigger a retry. Defaults to retrying on all errors.
///
/// - Throws: Rethrows the last error if all retry attempts fail or the error thrown by `clock`.
/// - Returns: The result of the successful operation execution if it completes within the retry limit.
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E, C>(
  maxAttempts: Int = 3,
  backoff backoffStrategy: BackoffStrategy<C, E> = .none(),
  clock: C,
  tolerance: C.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  if matchesError: (E) -> Bool = { _ in true }
) async throws -> R where C: Clock {
  
  precondition(maxAttempts > 0, "Retry must have at least one attempt")
  
  for attempt in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch {
      if matchesError(error) {
        try await clock.sleep(for: backoffStrategy.duration(attempt, error), tolerance: tolerance)
        continue
      } else {
        throw error
      }
    }
  }
  
  return try await operation()
}

/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// This function attempts to run the given `operation` a specified number of times (`maxAttempts`) in case of failure.
/// After each failed attempt that matches the specified error condition, it waits for a duration calculated
/// by the provided backoff strategy. This allows for a customizable retry policy with support for error matching,
/// delay between attempts, and clock tolerance. `ContinuousClock` will be used as the default clock.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - backoffStrategy: The strategy used to determine the delay between retry attempts. Defaults to `.none()`, meaning no delay.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to nil.
///   - isolation: The inherited actor isolation.
///   - operation: The asynchronous operation to perform, which may throw an error.
///   - matchesError: A closure that determines if an error thrown by `operation` should trigger a retry. Defaults to retrying on all errors.
///
/// - Throws: Rethrows the last error if all retry attempts fail or the error thrown by `clock`.
/// - Returns: The result of the successful operation execution if it completes within the retry limit.
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E>(
  maxAttempts: Int = 3,
  backoff backoffStrategy: BackoffStrategy<ContinuousClock, E> = .none(),
  tolerance: ContinuousClock.Duration? = nil,
  isolation: isolated (any Actor)? = #isolation,
  operation: () async throws(E) -> sending R,
  if matchesError: (E) -> Bool = { _ in true }
) async throws -> R {
  try await retry(maxAttempts: maxAttempts, backoff: backoffStrategy, clock: ContinuousClock(), tolerance: tolerance, operation: operation, if: matchesError)
}
#else
/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// This function attempts to run the given `operation` a specified number of times (`maxAttempts`) in case of failure.
/// After each failed attempt that matches the specified error condition, it waits for a duration calculated
/// by the provided backoff strategy. This allows for a customizable retry policy with support for error matching,
/// delay between attempts, and clock tolerance.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - backoffStrategy: The strategy used to determine the delay between retry attempts. Defaults to `.none()`, meaning no delay.
///   - clock: The clock used to wait for delays between retries.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to nil.
///   - operation: The asynchronous operation to perform, which may throw an error.
///   - matchesError: A closure that determines if an error thrown by `operation` should trigger a retry. Defaults to retrying on all errors.
///
/// - Throws: Rethrows the last error if all retry attempts fail or the error thrown by `clock`.
/// - Returns: The result of the successful operation execution if it completes within the retry limit.
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E, C>(
  maxAttempts: Int = 3,
  backoff backoffStrategy: BackoffStrategy<C, E> = .none(),
  clock: C,
  tolerance: C.Duration? = nil,
  operation: () async throws(E) -> sending R,
  if matchesError: (E) -> Bool = { _ in true }
) async throws -> R where C: Clock {
  
  precondition(maxAttempts > 0, "Retry must have at least one attempt")
  
  for attempt in 0..<maxAttempts - 1 {
    do {
      return try await operation()
    } catch {
      if matchesError(error) {
        try await clock.sleep(for: backoffStrategy.duration(attempt, error), tolerance: tolerance)
        continue
      } else {
        throw error
      }
    }
  }
  
  return try await operation()
}

/// Executes an asynchronous operation with a retry mechanism, applying a backoff strategy between attempts.
///
/// This function attempts to run the given `operation` a specified number of times (`maxAttempts`) in case of failure.
/// After each failed attempt that matches the specified error condition, it waits for a duration calculated
/// by the provided backoff strategy. This allows for a customizable retry policy with support for error matching,
/// delay between attempts, and clock tolerance. `ContinuousClock` will be used as the default clock.
///
/// - Parameters:
///   - maxAttempts: The maximum number of attempts to retry the operation. Defaults to 3.
///   - backoffStrategy: The strategy used to determine the delay between retry attempts. Defaults to `.none()`, meaning no delay.
///   - tolerance: An optional tolerance for the delay duration to account for clock imprecision. Defaults to nil.
///   - operation: The asynchronous operation to perform, which may throw an error.
///   - matchesError: A closure that determines if an error thrown by `operation` should trigger a retry. Defaults to retrying on all errors.
///
/// - Throws: Rethrows the last error if all retry attempts fail or the error thrown by `clock`.
/// - Returns: The result of the successful operation execution if it completes within the retry limit.
/// - Precondition: `maxAttempts` must be greater than 0.
public func retry<R, E>(
  maxAttempts: Int = 3,
  backoff backoffStrategy: BackoffStrategy<ContinuousClock, E> = .none(),
  tolerance: ContinuousClock.Duration? = nil,
  operation: () async throws(E) -> sending R,
  if matchesError: (E) -> Bool = { _ in true }
) async throws -> R {
  try await retry(maxAttempts: maxAttempts, backoff: backoffStrategy, clock: ContinuousClock(), tolerance: tolerance, operation: operation, if: matchesError)
}
#endif
