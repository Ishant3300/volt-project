import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/contants.dart';

/// A single tappable row in the Profile / Settings / Admin Settings / Reports
/// menus, rendered in the style of the active brand.
///
/// | | Apex | Volt |
/// |---|---|---|
/// | tile shape | circle | rounded square |
/// | tile fill | one neutral grey | per-item accent colour |
/// | icon colour | brand navy | white |
/// | tile / icon size | 32 / 16 | 40 / 21 |
/// | row height | compact (9px padding) | taller (14px padding) |
///
/// All of that comes from the `kMenuTile*` / `kMenuRow*` tokens in
/// `lib/config/app_brand.dart`, so this is the single place menu rows are
/// styled — the four menu screens just describe their content.
class BrandMenuRow extends StatelessWidget {
  const BrandMenuRow({
    super.key,
    required this.label,
    this.onTap,
    this.svgPath,
    this.icon,
    this.isDestructive = false,
    this.accentColor,
    this.trailing,
    this.horizontalPadding = 16,
    this.showBottomBorder = false,
  }) : assert(svgPath != null || icon != null,
            'BrandMenuRow needs either an svgPath or an icon');

  /// Row text, and the key used to pick this row's accent colour on Volt.
  final String label;

  final VoidCallback? onTap;

  /// Icon source — supply exactly one of these.
  final String? svgPath;
  final IconData? icon;

  /// Renders the label and chevron in red (Logout / Delete Account).
  final bool isDestructive;

  /// Overrides the accent colour that would otherwise be derived from [label].
  /// Ignored on brands where tiles are not colourful (i.e. Apex).
  final Color? accentColor;

  /// Optional widget shown immediately after the label — e.g. a progress
  /// spinner while logging out.
  final Widget? trailing;

  /// Some screens sit inside a card that already provides side padding.
  final double horizontalPadding;

  /// Draws a hairline under the row. Convenience for screens that don't emit
  /// their own dividers.
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    final foreground =
        isDestructive ? kMenuRowDestructiveColor : kMenuRowLabelColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: kMenuRowVerticalPadding,
        ),
        decoration: showBottomBorder
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(width: 1, color: kMenuRowDividerColor),
                ),
              )
            : null,
        child: Row(
          children: [
            BrandMenuIconTile(
              label: label,
              svgPath: svgPath,
              icon: icon,
              isDestructive: isDestructive,
              accentColor: accentColor,
            ),
            SizedBox(width: kMenuRowIconLabelGap),
            // A single Expanded claims all the space between the tile and the
            // chevron, which is what keeps every chevron on the same x position
            // regardless of label length. (An earlier version paired Flexible
            // with Spacer — both default to flex:1, so they split the free space
            // and the chevron drifted with the text.)
            //
            // The label has no maxLines/overflow, so long labels wrap onto a
            // second line instead of being truncated with an ellipsis.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: kFontSizeMenuItem,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ),
                  // Kept next to the label (not out by the chevron) so the
                  // logout spinner reads as part of the row's text.
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: kMenuChevronSize,
              color: isDestructive
                  ? kMenuRowDestructiveColor
                  : kMenuRowChevronColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Just the icon tile from a [BrandMenuRow].
///
/// Exposed for rows that share the menu look but not the menu layout — e.g. the
/// Two-Factor Auth row in Admin Settings, which has a subtitle and a toggle
/// instead of a chevron. Using this keeps such rows visually consistent with the
/// plain menu rows sitting beside them in the same card.
class BrandMenuIconTile extends StatelessWidget {
  const BrandMenuIconTile({
    super.key,
    required this.label,
    this.svgPath,
    this.icon,
    this.isDestructive = false,
    this.accentColor,
  }) : assert(svgPath != null || icon != null,
            'BrandMenuIconTile needs either an svgPath or an icon');

  /// Used to derive the accent colour on colourful brands.
  final String label;
  final String? svgPath;
  final IconData? icon;
  final bool isDestructive;
  final Color? accentColor;

  Color get _background {
    if (!kMenuTileColourful) {
      return isDestructive ? kMenuTileDestructiveBg : kMenuTileNeutralBg;
    }
    return accentColor ?? menuAccentFor(label);
  }

  Color get _iconColor {
    if (kMenuTileColourful) return Colors.white;
    return isDestructive ? kMenuRowDestructiveColor : kMenuTileNeutralIcon;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _iconColor;
    return Container(
      width: kMenuTileSize,
      height: kMenuTileSize,
      decoration: BoxDecoration(
        color: _background,
        shape: kMenuTileIsCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: kMenuTileIsCircle
            ? null
            : BorderRadius.circular(kMenuTileCornerRadius),
      ),
      child: Center(
        child: svgPath != null
            ? SvgPicture.asset(
                svgPath!,
                width: kMenuTileIconSize,
                height: kMenuTileIconSize,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              )
            : Icon(icon, size: kMenuTileIconSize, color: iconColor),
      ),
    );
  }
}

// ─── Volt accent palette ────────────────────────────────────────────────────
//
// Only consulted when `kMenuTileColourful` is true. Keyed by row label so the
// four menu screens need no colour arguments threaded through their call sites.

const Color _brown = Color(0xFFA1785B);
const Color _pink = Color(0xFFFF3B5C);
const Color _magenta = Color(0xFFC026D3);
const Color _indigo = Color(0xFF5B5BE6);
const Color _grey = Color(0xFF8E8E93);
const Color _green = Color(0xFF34C759);
const Color _cyan = Color(0xFF00BCD4);
const Color _teal = Color(0xFF14B8A6);
const Color _red = Color(0xFFFF3B30);
const Color _black = Color(0xFF000000);
const Color _orange = Color(0xFFFF7A2F);
const Color _deepOrange = Color(0xFFFF5722);
const Color _lightBlue = Color(0xFF2AA9E0);
const Color _blue = Color(0xFF1E88E5);
const Color _yellow = Color(0xFFFFC800);

const Map<String, Color> _menuAccents = {
  // Profile
  'Admin Setting': _brown,
  'Account Detail': _pink,
  'Master And User Management': _magenta,
  'Reports': _indigo,
  'Manage Reports': _indigo,
  'Settings': _grey,
  'Invite Friends': _green,
  'Login History': _cyan,
  'Switch Account': _teal,
  'Logout': _red,
  'Delete Account': _black,

  // Settings
  'Market Hours': _brown,
  'Set Quantity Values': _orange,
  'Change Password': _green,
  'Notification': _deepOrange,
  'Privacy Policy': _cyan,
  'Rules And Regulations': _lightBlue,

  // Admin settings
  'Reset TOTP Configuration': _grey,
  'Manage Instruments': Color(0xFFFF6B1A),
  'Send Message': _yellow,
  'Settlement': _blue,
  'Fetch Settlement Prices': _teal,
  'Group Quantity': _magenta,
  'Script Quantity': _orange,
  'Brokerage Settings': _green,
  'Fresh Stop-Loss Limits': Color(0xFFEF4444),

  // Reports
  'Account Summary': _blue,
  'Profit & Loss': _green,
  'Generate PDF': _pink,
  'Weekly Admin Report': _indigo,
  'Intraday History': _orange,
  'Userwise Open Position': _magenta,
  'Script Qty Details': _teal,
  'Deleted Trades': Color(0xFFEF4444),
  'Rejection Log History': _brown,
};

/// Fallback palette for labels not listed above, so a newly added menu item
/// still gets a sensible, stable colour without touching this file.
const List<Color> _fallbackPalette = [
  _blue,
  _green,
  _orange,
  _magenta,
  _teal,
  _indigo,
  _cyan,
  _deepOrange,
];

/// Accent colour for a menu row on colourful brands. Deterministic: the same
/// label always yields the same colour.
Color menuAccentFor(String label) {
  final mapped = _menuAccents[label];
  if (mapped != null) return mapped;
  var hash = 0;
  for (final unit in label.codeUnits) {
    hash = (hash + unit) & 0x7fffffff;
  }
  return _fallbackPalette[hash % _fallbackPalette.length];
}
