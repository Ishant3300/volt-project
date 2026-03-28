import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class SetQuantityValuesView extends StatefulWidget {
  const SetQuantityValuesView({super.key});
  @override
  State<SetQuantityValuesView> createState() => _SetQuantityValuesViewState();
}

class _SetQuantityValuesViewState extends State<SetQuantityValuesView> {
  final _storage = SecureStorageService();
  List<int> _values = [];
  bool _isLoading = true;

  static const _defaults = [100, 200, 500, 1000, 2000, 5000];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vals = await _storage.getQuickQuantities();
    setState(() { _values = vals; _isLoading = false; });
  }

  Future<void> _save() async {
    await _storage.saveQuickQuantities(_values);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved'), backgroundColor: Color(0xFF10B981)));
  }

  void _reset() {
    setState(() => _values = List.from(_defaults));
  }

  void _addBox() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add Quantity', style: TextStyle(fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, fontSize: kFontSizeSectionHeader)),
      content: TextField(
        controller: ctrl, autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
        decoration: InputDecoration(
          hintText: 'Enter quantity', hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: 'Inter'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), filled: true, fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3F45C7), width: 1.5))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter'))),
        GestureDetector(
          onTap: () {
            final v = int.tryParse(ctrl.text);
            if (v != null && v > 0) { setState(() => _values.add(v)); Navigator.pop(ctx); }
          },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(10)),
            child: const Text('Add', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, fontSize: kFontSizeBodySmall))),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium))),
          const SizedBox(width: 12),
          const Expanded(child: Text('Set Quantity Values', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
        ])),

        // Grid of quantity boxes
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
          : Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
              const Text('These values appear as quick quantity buttons on the trade card.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter')),
              const SizedBox(height: 12),
              Expanded(child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.8),
                itemCount: _values.length,
                itemBuilder: (_, i) => _qtyTile(i),
              )),
            ])),
        ),

        // Add box button
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GestureDetector(
          onTap: _addBox,
          child: Container(height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: Colors.white, size: 18), SizedBox(width: 6),
              Text('ADD BOX', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
            ])),
        )),
        const SizedBox(height: 12),

        // Reset + Update
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: _reset,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
              child: const Text('RESET', style: TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: _save,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(12)),
              child: const Text('UPDATE', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
          )),
        ])),
      ])),
    );
  }

  Widget _qtyTile(int index) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Stack(children: [
        Center(child: Text('${_values[index]}', style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
        Positioned(top: 4, right: 4, child: GestureDetector(
          onTap: () {
            if (_values.length <= 1) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Need at least one quantity'))); return; }
            setState(() => _values.removeAt(index));
          },
          child: Container(width: 24, height: 24,
            decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.close, size: kIconSizeSmall, color: Color(0xFFEF4444))),
        )),
      ]),
    );
  }
}
