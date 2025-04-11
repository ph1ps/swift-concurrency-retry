#if canImport(Testing)
import os
import Retry
import Testing

struct CustomError: Error { }

@Test func testBackoffRetryStrategy() async {
  
  var counter = 0
  await #expect(throws: CustomError.self) {
    try await retry(maxAttempts: 3, clock: ImmediateClock()) {
      counter += 1
      throw CustomError()
    }
  }
  
  #expect(counter == 3)
}

@Test func testStopRetryStrategy() async {
  
  var counter = 0
  await #expect(throws: CustomError.self) {
    try await retry(maxAttempts: 3, clock: UnimplementedClock()) {
      counter += 1
      throw CustomError()
    } strategy: { _ in
      return .stop
    }
  }
  
  #expect(counter == 1)
}

@Test func testCancellationInOperation() async {
  
  let testClock = TestClock()
  let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
  
  let task = Task {
    try await retry(maxAttempts: 3, clock: UnimplementedClock()) {
      counter.withLock { $0 += 1 }
      try await testClock.sleep(until: .init(offset: .seconds(1)))
    }
  }
  
  task.cancel()
  
  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  counter.withLock { value in
    #expect(value == 1)
  }
}

@Test func testCancellationInClock() async {
  
  let testClock = TestClock()
  let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
  
  let task = Task {
    try await retry(maxAttempts: 3, clock: testClock) {
      counter.withLock { $0 += 1 }
      throw CustomError()
    } strategy: { _ in
      return .backoff(.constant(.seconds(1)))
    }
  }
  
  await testClock.advance(by: .seconds(0.5))
  task.cancel()
  
  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  counter.withLock { value in
    #expect(value == 1)
  }
}

@Test func testImmediateBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.none
  #expect(strategy.duration(0) == .seconds(0))
  #expect(strategy.duration(1) == .seconds(0))
  #expect(strategy.duration(2) == .seconds(0))
  #expect(strategy.duration(3) == .seconds(0))
}

@Test func testConstantBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.constant(.seconds(1))
  #expect(strategy.duration(0) == .seconds(1))
  #expect(strategy.duration(1) == .seconds(1))
  #expect(strategy.duration(2) == .seconds(1))
  #expect(strategy.duration(3) == .seconds(1))
}

@Test func testLinearBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.linear(a: .seconds(3), b: .seconds(2))
  #expect(strategy.duration(0) == .seconds(2))
  #expect(strategy.duration(1) == .seconds(5))
  #expect(strategy.duration(2) == .seconds(8))
  #expect(strategy.duration(3) == .seconds(11))
}

@Test func testExponentialBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.exponential(a: .seconds(3), b: 2)
  #expect(strategy.duration(0) == .seconds(3))
  #expect(strategy.duration(1) == .seconds(6))
  #expect(strategy.duration(2) == .seconds(12))
  #expect(strategy.duration(3) == .seconds(24))
}

@Test func testMaxBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.exponential(a: .seconds(3), b: 2).max(.seconds(10))
  #expect(strategy.duration(0) == .seconds(3))
  #expect(strategy.duration(1) == .seconds(6))
  #expect(strategy.duration(2) == .seconds(10))
  #expect(strategy.duration(3) == .seconds(10))
}

@Test func testMinBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.exponential(a: .seconds(3), b: 2).min(.seconds(7))
  #expect(strategy.duration(0) == .seconds(7))
  #expect(strategy.duration(1) == .seconds(7))
  #expect(strategy.duration(2) == .seconds(12))
  #expect(strategy.duration(3) == .seconds(24))
}

@available(iOS 18.0, macOS 15.0, macCatalyst 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
@Test func testJitterBackoffStrategy() {
  let strategy = BackoffStrategy<ContinuousClock>.exponential(a: .seconds(3), b: 2).jitter(using: Xoshiro(seed: 1))
  #expect(strategy.duration(0) == .init(secondsComponent: 2, attosecondsComponent: 162894527200761519))
  #expect(strategy.duration(1) == .init(secondsComponent: 5, attosecondsComponent: 574149987820172283))
  #expect(strategy.duration(2) == .init(secondsComponent: 0, attosecondsComponent: 699421850917031809))
  #expect(strategy.duration(3) == .init(secondsComponent: 8, attosecondsComponent: 988773637185598212))
}
#endif
