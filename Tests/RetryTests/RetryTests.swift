#if canImport(Testing)
import Clocks
import ConcurrencyExtras
import Retry
import Testing

struct CustomError: Error { }

@Test func testBackoffRetryStrategy() async {
  
  var counter = 0
  await #expect(throws: CustomError.self) {
    try await retry(maxAttempts: 3, clock: .immediate) {
      counter += 1
      throw CustomError()
    }
  }
  
  #expect(counter == 3)
}

@Test func testStopRetryStrategy() async {
  
  var counter = 0
  await #expect(throws: CustomError.self) {
    try await retry(maxAttempts: 3, clock: .unimplemented()) {
      counter += 1
      throw CustomError()
    } strategy: { _ in
      return .stop
    }
  }
  
  #expect(counter == 1)
}

@Test func testImmediateBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    return try await retry(maxAttempts: 3, clock: testClock) {
      throw CustomError()
    } strategy: { _ in
      return .backoff(.none)
    }
  }
  
  await testClock.advance(by: .zero)
  await #expect(throws: CustomError.self) {
    try await task.value
  }
}

@Test func testConstantBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    return try await retry(maxAttempts: 3, clock: testClock) {
      throw CustomError()
    } strategy: { _ in
      return .backoff(.constant(c: .seconds(1)))
    }
  }
  
  await testClock.advance(by: .seconds(1))
  await testClock.advance(by: .seconds(1))
  await #expect(throws: CustomError.self) {
    try await task.value
  }
}

@Test func testLinearBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    return try await retry(maxAttempts: 3, clock: testClock) {
      throw CustomError()
    } strategy: { _ in
      return .backoff(.linear(a: .seconds(3), b: .seconds(2)))
    }
  }
  
  await testClock.advance(by: .seconds(2))
  await testClock.advance(by: .seconds(5))
  await #expect(throws: CustomError.self) {
    try await task.value
  }
}

@Test func testCappedBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    return try await retry(maxAttempts: 3, clock: testClock) {
      throw CustomError()
    } strategy: { _ in
      return .backoff(.constant(c: .seconds(2)).max(.seconds(1)))
    }
  }
  
  await testClock.advance(by: .seconds(1))
  await testClock.advance(by: .seconds(1))
  await #expect(throws: CustomError.self) {
    try await task.value
  }
}

@Test func testCancellationInOperation() async {
  
  let testClock = TestClock()
  let counter = LockIsolated<Int>(0)
  
  let task = Task {
    try await retry(maxAttempts: 3, clock: .unimplemented()) {
      counter.withValue { $0 += 1 }
      try await testClock.sleep(until: .init(offset: .seconds(1)))
    }
  }
  
  task.cancel()
  
  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  #expect(counter.value == 1)
}

@Test func testCancellationInClock() async {
  
  let testClock = TestClock()
  let counter = LockIsolated<Int>(0)
  
  let task = Task {
    try await retry(maxAttempts: 3, clock: testClock) {
      counter.withValue { $0 += 1 }
      throw CustomError()
    } strategy: { _ in
      return .backoff(.constant(c: .seconds(1)))
    }
  }
  
  await testClock.advance(by: .seconds(0.5))
  task.cancel()
  
  await #expect(throws: CancellationError.self) {
    try await task.value
  }
  #expect(counter.value == 1)
}
#endif
