import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  Map<String, String> _defaultHeaders({String? token}) {
    final headers = {
      "Content-Type": "application/json",
    };

    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }

    return headers;
  }

  Future<http.Response> get(String endpoint, {String? token}) async {
    return await http.get(
      Uri.parse("$baseUrl$endpoint"),
      headers: _defaultHeaders(token: token),
    );
  }

  Future<http.Response> post(String endpoint, dynamic body,
      {String? token}) async {
    return await http.post(
      Uri.parse("$baseUrl$endpoint"),
      headers: _defaultHeaders(token: token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, dynamic body,
      {String? token}) async {
    return await http.put(
      Uri.parse("$baseUrl$endpoint"),
      headers: _defaultHeaders(token: token),
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint, {String? token}) async {
    return await http.delete(
      Uri.parse("$baseUrl$endpoint"),
      headers: _defaultHeaders(token: token),
    );
  }
}
