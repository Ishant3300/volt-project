import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class UserwisePositionFilterBottomSheet extends StatefulWidget {
  final String? initialExchange;
  final String? initialTradingsymbol;
  final String? initialUserId;
  final String? initialUserName;
  final String role; // USER, MASTER, ADMIN

  const UserwisePositionFilterBottomSheet({
    super.key,
    this.initialExchange,
    this.initialTradingsymbol,
    this.initialUserId,
    this.initialUserName,
    required this.role,
  });

  @override
  State<UserwisePositionFilterBottomSheet> createState() =>
      _UserwisePositionFilterBottomSheetState();
}

class _UserwisePositionFilterBottomSheetState
    extends State<UserwisePositionFilterBottomSheet> {
  final _exchanges = ['All', 'NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS'];
  String _selectedExchange = 'All';

  final _instCtrl = TextEditingController();
  List<Map<String, dynamic>> _instResults = [];
  Map<String, dynamic>? _selectedInst;
  bool _showInstDropdown = false;
  bool _isSearchingInst = false;

  final _userCtrl = TextEditingController();
  List<Map<String, dynamic>> _userResults = [];
  String? _selectedUserId;
  String? _selectedUserName;
  bool _showUserDropdown = false;
  bool _isSearchingUser = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialExchange != null) _selectedExchange = widget.initialExchange!;
    if (widget.initialTradingsymbol != null) _instCtrl.text = widget.initialTradingsymbol!;
    if (widget.initialUserId != null) {
      _selectedUserId = widget.initialUserId;
      _selectedUserName = widget.initialUserName;
      _userCtrl.text = widget.initialUserName ?? '';
    }
  }

  @override
  void dispose() {
    _instCtrl.dispose();
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchInstruments(String q) async {
    if (q.length < 2) {
      setState(() { _instResults = []; _showInstDropdown = false; });
      return;
    }
    setState(() => _isSearchingInst = true);
    try {
      final token = await SecureStorageService().getToken();
      final ex = _selectedExchange == 'All' ? '' : '&exchange=$_selectedExchange';
      final res = await ApiService(backendUrl).get(
        '/kite/instruments/search?q=$q$ex&limit=20', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() {
            _instResults = List<Map<String, dynamic>>.from(body['data']);
            _showInstDropdown = _instResults.isNotEmpty;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingInst = false);
  }

  Future<void> _searchUsers(String q) async {
    if (q.length < 2) {
      setState(() { _userResults = []; _showUserDropdown = false; });
      return;
    }
    setState(() => _isSearchingUser = true);
    try {
      final token = await SecureStorageService().getToken();
      final endpoint = widget.role == 'ADMIN' ? '/admin/users' : '/master/users';
      final res = await ApiService(backendUrl).get(
        '$endpoint?search=$q', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          final users = body['data']['users'];
          if (users != null) {
            setState(() {
              _userResults = List<Map<String, dynamic>>.from(users);
              _showUserDropdown = _userResults.isNotEmpty;
            });
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingUser = false);
  }

  void _apply() {
    Navigator.pop(context, {
      'exchange': _selectedExchange == 'All' ? null : _selectedExchange,
      'tradingsymbol': _selectedInst != null ? _selectedInst!['tradingsymbol'] : null,
      'userId': _selectedUserId,
      'userName': _selectedUserName,
    });
  }

  void _clear() {
    Navigator.pop(context, {
      'exchange': null,
      'tradingsymbol': null,
      'userId': null,
      'userName': null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: EdgeInsets.only(
        top: 24, left: 16, right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text('Filter Positions',
            style: TextStyle(color: Colors.black, fontSize: kFontSizeSheetTitle,
              fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
          const SizedBox(height: 16),

          // Exchange dropdown
          _buildLabel('Exchange'),
          const SizedBox(height: 6),
          _buildExchangeDropdown(),
          const SizedBox(height: 14),

          // Instrument search
          _buildLabel('Instrument'),
          const SizedBox(height: 6),
          _buildSearchField(
            controller: _instCtrl,
            hint: 'Search instrument...',
            isSearching: _isSearchingInst,
            onChanged: _searchInstruments,
            onClear: () {
              _instCtrl.clear();
              setState(() { _selectedInst = null; _instResults = []; _showInstDropdown = false; });
            },
          ),
          if (_showInstDropdown) _buildInstDropdown(),
          const SizedBox(height: 14),

          // User search (admin/master only)
          if (widget.role != 'USER') ...[
            _buildLabel('User'),
            const SizedBox(height: 6),
            _buildSearchField(
              controller: _userCtrl,
              hint: 'Search user...',
              isSearching: _isSearchingUser,
              onChanged: _searchUsers,
              onClear: () {
                _userCtrl.clear();
                setState(() { _selectedUserId = null; _selectedUserName = null; _userResults = []; _showUserDropdown = false; });
              },
            ),
            if (_showUserDropdown) _buildUserDropdown(),
            const SizedBox(height: 14),
          ],

          const SizedBox(height: 8),
          // Buttons
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _clear,
                child: Container(
                  height: 48, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Clear',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBody,
                      fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _apply,
                child: Container(
                  height: 48, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kBrandPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('View',
                    style: TextStyle(color: Colors.white, fontSize: kFontSizeBody,
                      fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
      style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSheetLabel,
        fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5));
  }

  Widget _buildExchangeDropdown() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedExchange,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, size: kIconSizeDefault, color: Color(0xFF94A3B8)),
          style: TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
          items: _exchanges.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() {
            _selectedExchange = v!;
            _selectedInst = null;
            _instCtrl.clear();
            _instResults = [];
            _showInstDropdown = false;
          }),
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required bool isSearching,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: 'Inter'),
          suffixIcon: isSearching
              ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary)))
              : (controller.text.isNotEmpty
                  ? GestureDetector(onTap: onClear,
                      child: Icon(Icons.close, size: kIconSizeDefault, color: Color(0xFF94A3B8)))
                  : Icon(Icons.search, size: kIconSizeDefault, color: Color(0xFF94A3B8))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildInstDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero, shrinkWrap: true,
        itemCount: _instResults.length,
        itemBuilder: (_, i) {
          final inst = _instResults[i];
          return GestureDetector(
            onTap: () => setState(() {
              _selectedInst = inst;
              _instCtrl.text = inst['tradingsymbol'] ?? '';
              _showInstDropdown = false;
              _instResults = [];
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                  color: const Color(0xFFF1F5F9),
                  width: i < _instResults.length - 1 ? 1 : 0)),
              ),
              child: Row(children: [
                Expanded(child: Text(inst['tradingsymbol'] ?? '',
                  style: TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall,
                    fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: -0.3))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                  child: Text(inst['instrument_type'] ?? '',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption,
                      fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero, shrinkWrap: true,
        itemCount: _userResults.length,
        itemBuilder: (_, i) {
          final u = _userResults[i];
          final uname = u['username'] ?? '';
          final name = u['name'] ?? '';
          return GestureDetector(
            onTap: () => setState(() {
              _selectedUserId = u['id'] ?? u['_id'];
              _selectedUserName = uname;
              _userCtrl.text = uname;
              _showUserDropdown = false;
              _userResults = [];
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                  color: const Color(0xFFF1F5F9),
                  width: i < _userResults.length - 1 ? 1 : 0)),
              ),
              child: Row(children: [
                Text(uname,
                  style: TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall,
                    fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(name,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter')),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
