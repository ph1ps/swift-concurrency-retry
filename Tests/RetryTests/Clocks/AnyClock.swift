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
final class AnyClock<Duration: DurationProtocol & Hashable>: Clock {
  struct Instant: InstantProtocol {
    let offset: Duration
    
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
  
  let _minimumResolution: @Sendable () -> Duration
  let _now: @Sendable () -> Instant
  let _sleep: @Sendable (Instant, Duration?) async throws -> Void
  
  init<C: Clock>(_ clock: C) where C.Instant.Duration == Duration {
    let start = clock.now
    self._now = { Instant(offset: start.duration(to: clock.now)) }
    self._minimumResolution = { clock.minimumResolution }
    self._sleep = { try await clock.sleep(until: start.advanced(by: $0.offset), tolerance: $1) }
  }
  
  var minimumResolution: Duration {
    self._minimumResolution()
  }
  
  var now: Instant {
    self._now()
  }
  
  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    try await self._sleep(deadline, tolerance)
  }
}
#endif
