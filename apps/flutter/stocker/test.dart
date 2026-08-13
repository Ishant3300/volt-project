import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const String backendUrl = 'http://localhost:3000';
  final adminToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjZhNjYzMjRmYmMyNDQ2MDE1MmMyNzM3OCIsInJvbGUiOiJhZG1pbiIsImlhdCI6MTc4NjUxMDg5NH0.UBn8iZz0414db1cZXkEU_LqoWS5TfjLLIdRnQ7UyV7A';
  
  print('==== Testing Script Quantity: Issue 1 (createScriptQuantity ownership check) ====');
  
  // 1. Get two different masters
  final mastersRes = await http.get(
    Uri.parse('$backendUrl/api/masters'),
    headers: {'Authorization': 'Bearer $adminToken'},
  );
  
  final mastersList = jsonDecode(mastersRes.body)['data']['masters'] as List;
  if (mastersList.length < 2) {
      print('Not enough masters to test');
      return;
  }
  
  final master1 = mastersList[0];
  final master2 = mastersList[1];
  
  final token1 = master1['active_token'];
  if (token1 == null) {
      print('Master 1 does not have an active token.');
      return;
  }
  
  print('Using Master 1: ${master1['username']}');
  print('Target Master 2 (unauthorized): ${master2['username']} (ID: ${master2['_id'] ?? master2['id']})');
  
  // 2. Master 1 tries to create script quantity for Master 2
  final createRes = await http.post(
    Uri.parse('$backendUrl/api/admin/script-quantities'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token1',
    },
    body: jsonEncode({
      'exchange_name': 'NSE',
      'script_name': 'RELIANCE',
      'lot_size': 1,
      'max_qty': 100,
      'brk_qty': 50,
      'owner_id': master2['_id'] ?? master2['id'],
      'owner_type': 'Master'
    }),
  );
  
  print('Response Status: ${createRes.statusCode}');
  print('Response Body: ${createRes.body}');
  
  if (createRes.statusCode == 403) {
      print('✅ Issue 1 FIXED: Master cannot create script quantity for an unauthorized owner.');
  } else {
      print('❌ Issue 1 NOT FIXED: Master was able to bypass ownership check.');
  }
}
