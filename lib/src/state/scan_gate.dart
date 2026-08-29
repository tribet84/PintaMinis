/// Holds a decoded code back until the camera has seen it more than once.
///
/// This is the single technique that separates a hobby scanner from a
/// commercial one, and it costs almost nothing. A correct read repeats
/// identically frame after frame while the pot sits in view; a misread of a
/// blurred or curved label lands on different digits each time, because the
/// noise driving it differs each time. Requiring the same value several times
/// inside a short window therefore discards misreads without discarding
/// anything real — the pot is in frame for a second or more, which is dozens
/// of frames.
///
/// A check digit alone is not enough to lean on: roughly one in ten random
/// misreads satisfies it by chance, and at scanner frame rates that is a
/// wrong pot on the shelf every few seconds of bad conditions.
class ScanGate {
  ScanGate({
    this.confirmations = 3,
    this.window = const Duration(milliseconds: 1500),
  }) : assert(confirmations >= 1);

  /// How many identical reads are needed before a code is believed.
  final int confirmations;

  /// How long a sighting counts towards that total. Bounded so that two
  /// unrelated glimpses of the same wrong code, minutes apart, never add up.
  final Duration window;

  final _sightings = <String, List<DateTime>>{};

  /// Offers one decoded code. Returns it once it has been confirmed enough
  /// times, and null while it is still only a candidate.
  String? offer(String code, DateTime now) {
    _prune(now);

    final times = _sightings.putIfAbsent(code, () => <DateTime>[]);
    times.add(now);

    if (times.length < confirmations) return null;

    // Believed. Forget it so a second pot showing the same code later has to
    // earn its own confirmations rather than riding on these.
    _sightings.remove(code);
    return code;
  }

  /// Drops sightings that have aged out, and any code left with none.
  void _prune(DateTime now) {
    _sightings.removeWhere((_, times) {
      times.removeWhere((seen) => now.difference(seen) > window);
      return times.isEmpty;
    });
  }

  /// Forgets every pending candidate.
  void reset() => _sightings.clear();
}
