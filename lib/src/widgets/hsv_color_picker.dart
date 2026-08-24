import 'package:flutter/material.dart';

/// A compact HSV colour picker: saturation/value box plus hue slider.
///
/// Hand-rolled instead of pulling a picker package: the whole thing is two
/// gradients and two gesture handlers, and every dependency is a supply
/// chain this hobby project has to trust forever.
class HsvColorPicker extends StatelessWidget {
  const HsvColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
  });

  /// Current selection. Kept as [HSVColor] by the OWNER, not converted from
  /// RGB here: a round-trip through RGB collapses hue for grey/white/black
  /// picks, which made the hue thumb snap to red mid-drag.
  final HSVColor color;

  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SaturationValueBox(color: color, onChanged: onChanged),
        const SizedBox(height: 12),
        _HueSlider(color: color, onChanged: onChanged),
      ],
    );
  }
}

class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    onChanged(color.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    final hueOnly = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 180);
        return GestureDetector(
          onPanDown: (d) => _pick(d.localPosition, size),
          onPanUpdate: (d) => _pick(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // White→hue across, then transparent→black down: together
                  // they paint the full S/V plane for the current hue.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white, hueOnly],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                  Positioned(
                    left: color.saturation * size.width - 10,
                    top: (1 - color.value) * size.height - 10,
                    child: _Thumb(color: color.toColor()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.color, required this.onChanged});

  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  static final _hues = [
    for (var h = 0; h <= 360; h += 60)
      HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(Offset local) {
          final hue = (local.dx / width).clamp(0.0, 1.0) * 360;
          onChanged(color.withHue(hue.clamp(0, 359.99)));
        }

        return GestureDetector(
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: SizedBox(
            height: 28,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: _hues),
                    ),
                  ),
                ),
                Positioned(
                  left: (color.hue / 360) * width - 10,
                  top: 4,
                  child: _Thumb(
                    color: HSVColor.fromAHSV(1, color.hue, 1, 1).toColor(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
      ),
    );
  }
}
