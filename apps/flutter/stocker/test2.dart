import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final baseUrl = 'http://localhost:3000/api';
  final masterToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY5ZGRkMzNiNjgxMTJlNTU3YTU3MGEyMyIsInJvbGUiOiJtYXN0ZXIiLCJpYXQiOjE3ODY1NDY0NDYsImV4cCI6MTc4OTEzODQ0Nn0.yedQrYdOEMAzvLEoqHX9EwGZgmxfHWvp9nb_Fi2GY04';

  final response = await http.delete(
    Uri.parse('$baseUrl/master/users/6a67a0a034c92773f19b053c/script-quantity/123'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $masterToken',
    },
  );

  print('Response Status: ${response.statusCode}');
  print('Response Body: ${response.body}');
}
