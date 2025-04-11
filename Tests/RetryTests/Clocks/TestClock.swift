// MIT License
//
// Copyright (c) 2023 Point-Free
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#if canImport(Testing)
import Testing
import Foundation

final class TestClock<Duration: DurationProtocol & Hashable>: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    let offset: Duration
    
    init(offset: Duration = .zero) {
      self.offset = offset
    }
    
    func advanced(by duration: Duration) -> Self {
      .init(offset: self.offset + duration)
    }
    
    func duration(to other: Self) -> Duration {
      other.offset - self.offset
    }
    
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.offset < rhs.offset
    }
  }
  
  var minimumResolution: Duration = .zero
  var now: Instant
  
  let lock = NSRecursiveLock()
  var suspensions:
  [(
    id: UUID,
    deadline: Instant,
    continuation: AsyncThrowingStream<Never, Error>.Continuation
  )] = []
  
  init(now: Instant = .init()) {
    self.now = now
  }
  
  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    try Task.checkCancellation()
    let id = UUID()
    do {
      let stream: AsyncThrowingStream<Never, Error>? = self.lock.sync {
        guard deadline >= self.now
        else {
          return nil
        }
        return AsyncThrowingStream<Never, Error> { continuation in
          self.suspensions.append((id: id, deadline: deadline, continuation: continuation))
        }
      }
      guard let stream = stream
      else { return }
      for try await _ in stream {}
      try Task.checkCancellation()
    } catch is CancellationError {
      self.lock.sync { self.suspensions.removeAll(where: { $0.id == id }) }
      throw CancellationError()
    } catch {
      throw error
    }
  }
  
  func checkSuspension() async throws {
    await Task.megaYield()
    guard self.lock.sync(operation: { self.suspensions.isEmpty })
    else { throw SuspensionError() }
  }
  
  func advance(by duration: Duration = .zero) async {
    await self.advance(to: self.lock.sync(operation: { self.now.advanced(by: duration) }))
  }
  
  func advance(to deadline: Instant) async {
    while self.lock.sync(operation: { self.now <= deadline }) {
      await Task.megaYield()
      let `return` = {
        self.lock.lock()
        self.suspensions.sort { $0.deadline < $1.deadline }
        
        guard
          let next = self.suspensions.first,
          deadline >= next.deadline
        else {
          self.now = deadline
          self.lock.unlock()
          return true
        }
        
        self.now = next.deadline
        self.suspensions.removeFirst()
        self.lock.unlock()
        next.continuation.finish()
        return false
      }()
      
      if `return` {
        await Task.megaYield()
        return
      }
    }
    await Task.megaYield()
  }
  
  func run(
    timeout duration: Swift.Duration = .milliseconds(500),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await Task.sleep(until: .now.advanced(by: duration), clock: .continuous)
          for suspension in self.suspensions {
            suspension.continuation.finish(throwing: CancellationError())
          }
          throw CancellationError()
        }
        group.addTask {
          await Task.megaYield()
          while let deadline = self.lock.sync(operation: { self.suspensions.first?.deadline }) {
            try Task.checkCancellation()
            await self.advance(by: self.lock.sync(operation: { self.now.duration(to: deadline) }))
          }
        }
        try await group.next()
        group.cancelAll()
      }
    } catch {
      let comment = Comment(rawValue:
          """
          Expected all sleeps to finish, but some are still suspending after \(duration).
          
          There are sleeps suspending. This could mean you are not advancing the test clock far \
          enough for your feature to execute its logic, or there could be a bug in your feature's \
          logic.
          
          You can also increase the timeout of 'run' to be greater than \(duration).
          """
      )
      Issue.record(comment)
    }
  }
}

struct SuspensionError: Error {}

extension Task where Success == Never, Failure == Never {
  static func megaYield(count: Int = 20) async {
    for _ in 0..<count {
      await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
    }
  }
}

extension NSRecursiveLock {
  @inlinable
  @discardableResult
  func sync<R>(operation: () -> R) -> R {
    self.lock()
    defer { self.unlock() }
    return operation()
  }
}

extension TestClock where Duration == Swift.Duration {
  convenience init() {
    self.init(now: .init())
  }
}
#endif
