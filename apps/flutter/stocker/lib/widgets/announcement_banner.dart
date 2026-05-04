import 'package:flutter/material.dart';
import '../services/announcement_service.dart';
import '../utils/contants.dart';

class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner>
    with SingleTickerProviderStateMixin {
  String? _message;
  late AnimationController _controller;
  bool _loaded = false;
  static const double _gap = 80;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _fetch();
  }

  Future<void> _fetch() async {
    final msg = await AnnouncementService().fetchActive();
    if (mounted) setState(() { _message = msg; _loaded = true; });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _measureText() {
    final tp = TextPainter(
      text: TextSpan(
        text: _message ?? '',
        style: const TextStyle(fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _message == null || _message!.isEmpty) {
      return const SizedBox.shrink();
    }

    const textStyle = TextStyle(
      color: Color(0xFFDC2626),
      fontSize: kFontSizeSubtitle,
      fontFamily: 'Inter',
      fontWeight: kFontWeightSemiBold,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFEE2E2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.campaign, color: Color(0xFFDC2626), size: kIconSizeDefault),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final textW = _measureText();
                  final cycleW = textW + _gap;
                  final offset = _controller.value * cycleW;
                  return Stack(
                    children: [
                      Positioned(
                        left: -offset,
                        top: 0,
                        bottom: 0,
                        child: Row(
                          children: [
                            Text(_message!, maxLines: 1, softWrap: false, style: textStyle),
                            SizedBox(width: _gap),
                            Text(_message!, maxLines: 1, softWrap: false, style: textStyle),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
