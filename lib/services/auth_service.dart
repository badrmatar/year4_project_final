// lib/services/auth_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final String userLoginFunctionUrl = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_login';

  Future<bool> userLogin(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse(userLoginFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          // Optionally, include authorization headers if required
          // 'Authorization': 'Bearer your_token',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Login successful: ${data['message']}');
        // Optionally, store user data or perform additional actions
        return true;
      } else {
        final error = jsonDecode(response.body);
        print('Login failed : ${error['error']}');
        return false;
      }
    } catch (e) {
      print('An unexpected error occurred: $e');
      return false;
    }
  }

  Future<bool> userLogout() async {
    // Implement logout logic if needed
    // Since you're handling custom auth, manage sessions as per your implementation
    // For example, clear stored tokens or user data
    return true;
  }

  Future<bool> signUp(String email, String password) async {
    // Implement sign-up logic by calling a similar Edge Function
    // Ensure passwords are hashed before sending or handle hashing in the Edge Function
    return true;
  }
}