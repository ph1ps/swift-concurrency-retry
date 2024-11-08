#if canImport(Testing)
import Clocks
import Retry
import Testing

struct CustomError: Error { }

@Test func testMaxAttemptsRetryStrategy() async {
  
  var counter = 0
  await #expect(throws: CustomError.self) {
    try await retry(maxAttempts: 3, backoff: .none(), clock: .immediate) {
      counter += 1
      throw CustomError()
    }
  }
  
  #expect(counter == 3)
}

@Test func testImmediateBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    var counter = 0
    return try await retry(maxAttempts: 3, backoff: .none(), clock: testClock) {
      counter += 1
      if counter == 3 {
        return "success"
      } else {
        throw CustomError()
      }
    }
  }
  
  await testClock.advance(by: .zero)
  try await #expect(task.value == "success")
}

@Test func testConstantBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    var counter = 0
    return try await retry(maxAttempts: 3, backoff: .constant(c: .seconds(1)), clock: testClock) {
      counter += 1
      if counter == 3 {
        return "success"
      } else {
        throw CustomError()
      }
    }
  }
  
  await testClock.advance(by: .seconds(1))
  await testClock.advance(by: .seconds(1))
  try await #expect(task.value == "success")
}

@Test func testLinearBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    var counter = 0
    return try await retry(maxAttempts: 3, backoff: .linear(a: .seconds(3), b: .seconds(2)), clock: testClock) {
      counter += 1
      if counter == 3 {
        return "success"
      } else {
        throw CustomError()
      }
    }
  }
  
  await testClock.advance(by: .seconds(2))
  await testClock.advance(by: .seconds(5))
  try await #expect(task.value == "success")
}

@Test func testCappedBackoffStrategy() async throws {
  
  let testClock = TestClock()
  let task = Task {
    var counter = 0
    return try await retry(maxAttempts: 3, backoff: .constant(c: .seconds(2)).max(.seconds(1)), clock: testClock) {
      counter += 1
      if counter == 3 {
        return "success"
      } else {
        throw CustomError()
      }
    }
  }
  
  await testClock.advance(by: .seconds(1))
  await testClock.advance(by: .seconds(1))
  try await #expect(task.value == "success")
}

@Test func testNotMatchingError() async {
  
  struct OtherError: Error { }
  
  var counter = 0
  await #expect(throws: OtherError.self) {
    try await retry(maxAttempts: 3, backoff: .none(), clock: .immediate) {
      counter += 1
      throw OtherError()
    } if: { error in
      false
    }
  }
  
  #expect(counter == 1)
}
#endif
