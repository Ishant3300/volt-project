import 'package:intl/intl.dart';

class DateFormatter {
  /// Formats ISO 8601 date string to readable format
  /// Example: "2026-02-18T06:31:57.219Z" -> "18 Feb 2026, 06:31 AM"
  static String formatDateTime(String? isoDateString) {
    if (isoDateString == null || isoDateString.isEmpty) {
      return 'Never';
    }

    try {
      final dateTime = DateTime.parse(isoDateString);
      final formatter = DateFormat('dd MMM yyyy, hh:mm a');
      return formatter.format(dateTime.toLocal());
    } catch (e) {
      return isoDateString; // Return original if parsing fails
    }
  }

  /// Formats ISO 8601 date string to date only
  /// Example: "2026-02-18T06:31:57.219Z" -> "18 Feb 2026"
  static String formatDate(String? isoDateString) {
    if (isoDateString == null || isoDateString.isEmpty) {
      return 'N/A';
    }

    try {
      final dateTime = DateTime.parse(isoDateString);
      final formatter = DateFormat('dd MMM yyyy');
      return formatter.format(dateTime.toLocal());
    } catch (e) {
      return isoDateString;
    }
  }

  /// Formats ISO 8601 date string to relative time
  /// Example: "2 hours ago", "3 days ago", etc.
  static String formatRelative(String? isoDateString) {
    if (isoDateString == null || isoDateString.isEmpty) {
      return 'Never';
    }

    try {
      final dateTime = DateTime.parse(isoDateString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} min ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours} hours ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return formatDate(isoDateString);
      }
    } catch (e) {
      return isoDateString;
    }
  }
}
