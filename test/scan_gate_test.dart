import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/state/scan_gate.dart';

void main() {
  final t0 = DateTime(2026, 8, 29, 12);

  test('one sighting is never enough to act on', () {
    final gate = ScanGate(confirmations: 3);
    expect(gate.offer('8429551709088', t0), isNull);
  });

  test('a code repeating across frames is believed', () {
    final gate = ScanGate(confirmations: 3);
    expect(gate.offer('8429551709088', t0), isNull);
    expect(
      gate.offer('8429551709088', t0.add(const Duration(milliseconds: 40))),
      isNull,
    );
    expect(
      gate.offer('8429551709088', t0.add(const Duration(milliseconds: 80))),
      '8429551709088',
    );
  });

  test('misreads that never agree are never emitted', () {
    // What a blurred, curved label actually produces: a different confident
    // answer every frame. None of them should reach the shelf.
    final gate = ScanGate(confirmations: 3);
    for (var i = 0; i < 30; i++) {
      final noise = '842955170${(9000 + i).toString()}';
      expect(
        gate.offer(noise, t0.add(Duration(milliseconds: 40 * i))),
        isNull,
      );
    }
  });

  test('a real code still gets through while misreads flicker around it', () {
    final gate = ScanGate(confirmations: 3);
    String? emitted;
    for (var i = 0; i < 6; i++) {
      final at = t0.add(Duration(milliseconds: 40 * i));
      // Alternate the true reading with a different wrong one each frame.
      emitted ??= gate.offer('8429551709088', at);
      gate.offer('842955170$i${i}00', at);
    }
    expect(emitted, '8429551709088');
  });

  test('sightings too far apart do not accumulate', () {
    // Two stray glimpses minutes apart are not evidence of the same pot.
    final gate = ScanGate(
      confirmations: 2,
      window: const Duration(milliseconds: 500),
    );
    expect(gate.offer('8429551709088', t0), isNull);
    expect(
      gate.offer('8429551709088', t0.add(const Duration(seconds: 30))),
      isNull,
      reason: 'the first sighting should have aged out',
    );
  });

  test('a confirmed code must earn its confirmations again', () {
    // Otherwise the frame right after acceptance would re-emit instantly.
    final gate = ScanGate(confirmations: 2);
    gate.offer('8429551709088', t0);
    expect(
      gate.offer('8429551709088', t0.add(const Duration(milliseconds: 40))),
      '8429551709088',
    );
    expect(
      gate.offer('8429551709088', t0.add(const Duration(milliseconds: 80))),
      isNull,
    );
  });

  test('reset clears pending candidates', () {
    final gate = ScanGate(confirmations: 2);
    gate.offer('8429551709088', t0);
    gate.reset();
    expect(
      gate.offer('8429551709088', t0.add(const Duration(milliseconds: 40))),
      isNull,
    );
  });
}
