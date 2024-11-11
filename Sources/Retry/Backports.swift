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
