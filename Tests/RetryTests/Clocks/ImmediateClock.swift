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
import Foundation

final class ImmediateClock<Duration>: Clock, @unchecked Sendable where Duration: DurationProtocol, Duration: Hashable {
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
  
  var now: Instant
  var minimumResolution: Duration = .zero
  let lock = NSLock()
  
  init(now: Instant = .init()) {
    self.now = now
  }
  
  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    try Task.checkCancellation()
    self.lock.sync { self.now = deadline }
    await Task.megaYield()
  }
}

extension ImmediateClock where Duration == Swift.Duration {
  convenience init() {
    self.init(now: .init())
  }
}

extension NSLock {
  @inlinable
  @discardableResult
  func sync<R>(operation: () -> R) -> R {
    self.lock()
    defer { self.unlock() }
    return operation()
  }
}
#endif
