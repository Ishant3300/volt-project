import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('🧪 Testing Master API Response Structure\n');
  
  // Get token from command line argument
  if (Platform.environment['TOKEN'] == null || Platform.environment['TOKEN']!.isEmpty) {
    print('❌ Please provide TOKEN environment variable');
    print('Usage: TOKEN=your_token_here dart test/run_master_test.dart');
    exit(1);
  }
  
  final token = Platform.environment['TOKEN']!;
  const baseUrl = 'http://127.0.0.1:3000';
  
  try {
    print('📡 Fetching masters from: $baseUrl/api/masters?page=1&limit=1\n');
    
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
      print('✅ Full Response:');
      print(JsonEncoder.withIndent('  ').convert(data));
      print('\n');
      
      if (data['data'] != null && data['data']['masters'] != null) {
        final masters = data['data']['masters'] as List;
        if (masters.isNotEmpty) {
          print('📋 First Master Object:');
          print(JsonEncoder.withIndent('  ').convert(masters[0]));
          print('\n');
          
          final master = masters[0] as Map<String, dynamic>;
          print('🔍 Field Types Analysis:');
          print('=' * 60);
          master.forEach((key, value) {
            final type = value.runtimeType;
            final valueStr = value.toString().length > 50 
                ? '${value.toString().substring(0, 50)}...' 
                : value.toString();
            print('  $key:');
            print('    Type: $type');
            print('    Value: $valueStr');
          });
          print('=' * 60);
        } else {
          print('⚠️  No masters found in response');
        }
      } else {
        print('⚠️  No masters data in response');
      }
    } else if (response.statusCode == 401) {
      print('❌ Unauthorized - Token may be invalid or expired');
      print('Response: ${response.body}');
    } else {
      print('❌ Error Response:');
      print(response.body);
    }
  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
  }
}
