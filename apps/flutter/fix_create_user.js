const fs = require('fs');
const path = './lib/views/create_user_view.dart';
let code = fs.readFileSync(path, 'utf8');

// 1. Remove _brokerageSettings map declaration
code = code.replace(/final Map<String, dynamic> _brokerageSettings = {[^;]+;/g, '');

// 2. Remove _applyBrokerageSettings function
code = code.replace(/Future<void> _applyBrokerageSettings\(\) async {[\s\S]*?(?=\s*@override)/g, '');

// 3. Remove dispose calls for _brokerageSettings
code = code.replace(/for \(final entry in _brokerageSettings\.values\) {[\s\S]*?}\n/g, '');

// 4. Remove _applyBrokerageSettings call inside _saveData
code = code.replace(/\/\/ Apply brokerage settings for enabled exchanges\s*await _applyBrokerageSettings\(\);\s*/g, '');

// 5. Remove UI section for Brokerage Settings (inline)
code = code.replace(/\/\/ Brokerage Settings \(inline\)\s*_sectionLabel\('BROKERAGE SETTINGS'\),\s*const SizedBox\(height: 12\),\s*_card\([\s\S]*?\.\.\._allowedExchanges\.map\(\(exchange\) => _buildBrokerageRow\(exchange\)\),\s*\],\s*\),\s*\),\s*const SizedBox\(height: 24\),\s*/g, '');

// 6. Remove _buildBrokerageRow method
code = code.replace(/Widget _buildBrokerageRow\(String exchange\) {[\s\S]*?(?=Widget _sectionLabel\(String label\))/g, '');

fs.writeFileSync(path, code);
console.log("create_user_view.dart updated!");
