// Trick from swift-numerics to get pow without Foundation
static inline __attribute__((__always_inline__)) long pow(long x, long y) {
  return __builtin_pow(x, y);
}
