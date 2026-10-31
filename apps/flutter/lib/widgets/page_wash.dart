import 'package:flutter/material.dart';
import '../utils/contants.dart';

/// A soft brand-blue wash at the top of a screen (1 Nov 2026): starts under
/// the status bar and fades into the page, so the header row needs no colour
/// of its own. Colour only — the screen's layout is untouched ([child] fills
/// the same space it did as the Scaffold body).
class PageWash extends StatelessWidget {
  final Widget child;
  const PageWash({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 240,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kWashTop, kWashMid, Color(0x00EBF0FF)],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
