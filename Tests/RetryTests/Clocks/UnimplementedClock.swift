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

struct UnimplementedClock<Duration: DurationProtocol & Hashable>: Clock {
  struct Instant: InstantProtocol {
    let rawValue: AnyClock<Duration>.Instant
    
    func advanced(by duration: Duration) -> Self {
      Self(rawValue: self.rawValue.advanced(by: duration))
    }
    
    func duration(to other: Self) -> Duration {
      self.rawValue.duration(to: other.rawValue)
    }
    
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
  
  let base: AnyClock<Duration>
  let name: String
  let fileID: StaticString
  let filePath: StaticString
  let line: UInt
  let column: UInt
  
  init<C: Clock>(
    _ base: C,
    name: String = "\(C.self)",
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) where C.Duration == Duration {
    self.base = AnyClock(base)
    self.name = name
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }
  
  init(
    name: String = "Clock",
    now: ImmediateClock<Duration>.Instant = .init(),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    self.init(
      ImmediateClock(now: now),
      name: name,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
  }
  
  var now: Instant {
    Issue.record("Unimplemented: \(self.name).now")
    return Instant(rawValue: self.base.now)
  }
  
  var minimumResolution: Duration {
    Issue.record("Unimplemented: \(self.name).minimumResolution")
    return self.base.minimumResolution
  }
  
  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    Issue.record("Unimplemented: \(self.name).sleep")
    try await self.base.sleep(until: deadline.rawValue, tolerance: tolerance)
  }
}

extension UnimplementedClock where Duration == Swift.Duration {
  init(name: String = "Clock") {
    self.init(name: name, now: .init())
  }
}
#endif
