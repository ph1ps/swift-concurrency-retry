// MIT License
//
// Copyright (c) 2019 Point-Free, Inc.
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
// An implementation of xoshiro256**: http://xoshiro.di.unimi.it.
public struct Xoshiro: RandomNumberGenerator {
  @usableFromInline
  var state: (UInt64, UInt64, UInt64, UInt64)
  
  @inlinable
  public init(seed: UInt64) {
    self.state = (seed, 18_446_744, 073_709, 551_615)
    for _ in 1...10 { _ = self.next() }  // perturb
  }
  
  @inlinable
  public mutating func next() -> UInt64 {
    // Adopted from https://github.com/mattgallagher/CwlUtils/blob/0bfc4587d01cfc796b6c7e118fc631333dd8ab33/Sources/CwlUtils/CwlRandom.swift
    let x = self.state.1 &* 5
    let result = ((x &<< 7) | (x &>> 57)) &* 9
    let t = self.state.1 &<< 17
    self.state.2 ^= self.state.0
    self.state.3 ^= self.state.1
    self.state.1 ^= self.state.2
    self.state.0 ^= self.state.3
    self.state.2 ^= t
    self.state.3 = (self.state.3 &<< 45) | (self.state.3 &>> 19)
    return result
  }
}
