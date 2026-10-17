import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

/// Masters the logged-in account may create an account for, as
/// `{id, name, username, add_master}` sorted by name: a master's whole
/// downline (`GET /api/master/downline-masters`), or every master for admin
/// (`GET /api/masters?include_submasters=true`). Empty on any failure.
Future<List<Map<String, dynamic>>> loadCreateForMasters({required bool isAdmin}) async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).get(
        isAdmin
            ? '/masters?include_submasters=true&limit=1000'
            : '/master/downline-masters',
        token: token);
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body);
    if (body['success'] != true) return [];
    final data = body['data'];
    final raw = isAdmin ? (data is Map ? data['masters'] : null) : data;
    final list = <Map<String, dynamic>>[
      for (final m in (raw as List? ?? const []))
        if (m is Map)
          {
            'id': (m['id'] ?? m['_id'])?.toString(),
            'name': m['name']?.toString() ?? '',
            'username': m['username']?.toString() ?? '',
            'add_master': m['add_master'] == true,
          }
    ]..removeWhere((m) => m['id'] == null);
    list.sort((a, b) => (a['name'] as String)
        .toLowerCase()
        .compareTo((b['name'] as String).toLowerCase()));
    return list;
  } catch (e) {
    log('⚠️ Error loading create-for masters: $e');
    return [];
  }
}

/// "Create account for" — who will own the new client / sub-master. Defaults
/// to the logged-in account ("Myself"); tapping opens a searchable list of
/// the masters below them (admin: every master). The chosen master becomes
/// the new account's parent: it owns and funds it, and its brokerage rates,
/// limits and sharing apply (backend: `for_master_id`). Shared by
/// create_user_view.dart and create_master_view.dart; the screens own the
/// state and just render this.
///
/// [masters] entries: `{id, name, username, add_master}` — from
/// `GET /api/master/downline-masters` (master) or `GET /api/masters` (admin).
class CreateForMasterPicker extends StatelessWidget {
  const CreateForMasterPicker({
    super.key,
    required this.masters,
    required this.selectedId,
    required this.selfLabel,
    required this.loading,
    required this.onSelect,
    this.requireAddMaster = false,
  });

  final List<Map<String, dynamic>> masters;

  /// null = the logged-in account itself.
  final String? selectedId;

  /// "Myself — …" row, or null when the caller can't own it themselves
  /// (admin creating a client must pick a master).
  final String? selfLabel;
  final bool loading;

  /// Creating a sub-master: masters without the "create sub-master"
  /// permission are shown but can't be picked.
  final bool requireAddMaster;
  final ValueChanged<String?> onSelect;

  static String labelOf(Map<String, dynamic> m) =>
      '${m['name'] ?? ''} (${m['username'] ?? ''})';

  String get _currentLabel {
    if (selectedId == null) return selfLabel ?? 'Select master';
    for (final m in masters) {
      if (m['id']?.toString() == selectedId) return labelOf(m);
    }
    return 'Select master';
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreateForSheet(
        masters: masters,
        selectedId: selectedId,
        selfLabel: selfLabel,
        requireAddMaster: requireAddMaster,
      ),
    );
    if (picked == null) return; // dismissed
    final id = picked == _CreateForSheet.self ? null : picked;
    if (id != selectedId) onSelect(id);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = selectedId == null && selfLabel == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create account for',
            style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 13,
                color: kColorTextMuted,
                fontWeight: kFontWeightMedium),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: loading ? null : () => _open(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 14,
                        fontWeight:
                            placeholder ? FontWeight.w400 : kFontWeightSemiBold,
                        color: placeholder
                            ? kColorTextMuted
                            : kColorTextPrimary,
                      ),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: kColorTextMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateForSheet extends StatefulWidget {
  const _CreateForSheet({
    required this.masters,
    required this.selectedId,
    required this.selfLabel,
    required this.requireAddMaster,
  });

  static const self = '__self__';

  final List<Map<String, dynamic>> masters;
  final String? selectedId;
  final String? selfLabel;
  final bool requireAddMaster;

  @override
  State<_CreateForSheet> createState() => _CreateForSheetState();
}

class _CreateForSheetState extends State<_CreateForSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.masters
        .where((m) =>
            q.isEmpty ||
            '${m['name'] ?? ''} ${m['username'] ?? ''}'
                .toLowerCase()
                .contains(q))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Text(
                'Create account for',
                style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: kFontSizeViewTitle,
                    fontWeight: kFontWeightBold,
                    color: kColorTextPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Search name or ID',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.selfLabel != null && q.isEmpty)
                    _row(
                      label: widget.selfLabel!,
                      selected: widget.selectedId == null,
                      enabled: true,
                      value: _CreateForSheet.self,
                    ),
                  for (final m in rows)
                    _row(
                      label: CreateForMasterPicker.labelOf(m),
                      selected: m['id']?.toString() == widget.selectedId,
                      enabled: !widget.requireAddMaster ||
                          m['add_master'] == true,
                      value: m['id']?.toString() ?? '',
                    ),
                  if (rows.isEmpty && q.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No master matches',
                            style: TextStyle(
                                fontFamily: kFontFamily,
                                color: kColorTextMuted)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required bool selected,
    required bool enabled,
    required String value,
  }) {
    return InkWell(
      onTap: enabled ? () => Navigator.pop(context, value) : null,
      child: Container(
        color: selected ? const Color(0xFFEFF6FF) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: kFontFamily,
                  fontSize: 14,
                  fontWeight: selected ? kFontWeightSemiBold : FontWeight.w400,
                  color: !enabled
                      ? kColorTextMuted
                      : selected
                          ? kBrandPrimary
                          : kColorTextPrimary,
                ),
              ),
            ),
            if (!enabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('no sub-master rights',
                    style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 11,
                        color: Color(0xFFB45309))),
              )
            else if (selected)
              const Icon(Icons.check, size: 18, color: kBrandPrimary),
          ],
        ),
      ),
    );
  }
}
