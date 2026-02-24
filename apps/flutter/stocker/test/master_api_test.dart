import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('🧪 Testing Master API Response Structure\n');
  
  // Replace with your actual token
  const token = 'YOUR_TOKEN_HERE';
  const baseUrl = 'http://127.0.0.1:3000';
  
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/masters?page=1&limit=1'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    
    print('Status Code: ${response.statusCode}\n');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('Full Response:');
      print(JsonEncoder.withIndent('  ').convert(data));
      print('\n');
      
      if (data['data'] != null && data['data']['masters'] != null) {
        final masters = data['data']['masters'] as List;
        if (masters.isNotEmpty) {
          print('First Master Object:');
          print(JsonEncoder.withIndent('  ').convert(masters[0]));
          print('\n');
          
          final master = masters[0] as Map<String, dynamic>;
          print('Field Types:');
          master.forEach((key, value) {
            print('  $key: ${value.runtimeType} = $value');
          });
        } else {
          print('No masters found in response');
        }
      }
    } else {
      print('Error Response:');
      print(response.body);
    }
  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
  }
}
