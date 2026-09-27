import 'package:flutter/material.dart';
import '../utils/contants.dart';

/// "Create account for" — lets a master create a client or sub-master ON
/// BEHALF of a master in their own downline (e.g. harry creating a client
/// for his sub-master vijay). The chosen master becomes the new account's
/// parent: it owns and funds it, and its brokerage rates, limits and sharing
/// apply (backend: `for_master_id`). Shared by create_user_view.dart and
/// create_master_view.dart; the screens own the state and just render this.
///
/// [masters] are entries of `GET /api/master/downline-masters`.
class CreateForMasterPicker extends StatelessWidget {
  const CreateForMasterPicker({
    super.key,
    required this.masters,
    required this.enabled,
    required this.selectedId,
    required this.loading,
    required this.ownerLabel,
    required this.onToggle,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> masters;
  final bool enabled;
  final String? selectedId;
  final bool loading;

  /// "Name (username)" of the currently loaded owner, or null while loading.
  final String? ownerLabel;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: enabled,
            title: const Text(
              'Create account for a sub-master',
              style: TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 14,
                  color: kColorTextPrimary),
            ),
            onChanged: loading ? null : (checked) => onToggle(checked == true),
          ),
          if (enabled) ...[
            DropdownButton<String>(
              isExpanded: true,
              value: selectedId ?? masters.first['id']?.toString(),
              items: masters.map((m) {
                final parent = m['parent'] is Map
                    ? ' — under ${(m['parent'] as Map)['username']}'
                    : '';
                return DropdownMenuItem<String>(
                  value: m['id']?.toString(),
                  child: Text(
                    '${m['name']} (${m['username']})$parent',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 14,
                        color: kColorTextPrimary),
                  ),
                );
              }).toList(),
              onChanged: loading ? null : onSelect,
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (ownerLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Owned and funded by $ownerLabel — the balance, brokerage '
                  'rates and limits below are theirs, not yours.',
                  style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 12,
                      color: Color(0xFFB45309)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
