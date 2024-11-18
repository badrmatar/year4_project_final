// lib/services/auth_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/user.dart';

class AuthService {
  final String userLoginFunctionUrl = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_login';
  final String userSignupFunctionUrl = 'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_signup';
  final String bearer_token = dotenv.env['BEARER_TOKEN']!;

  Future<bool> userLogin(BuildContext context, String email, String password) async {
    try {
      print('Sending login request with Email: $email and Password: $password'); // Remove password logging in production
      final response = await http.post(
        Uri.parse(userLoginFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearer_token'
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('Login successful: ${data['message']}');
        UpdateUserModel(context, data);
        return true;
      } else {
        final error = jsonDecode(response.body);
        print('Login failed: ${error['error']}');
        return false;
      }
    } catch (e) {
      print('An unexpected error occurred during login: $e');
      return false;
    }
  }

  Future<bool> registerUser(BuildContext context, String username, String email, String password) async {
    try {
      print('Sending registration request with Email: $email and Password: $password and name: $username'); // Remove password logging in production
      final response = await http.post(
        Uri.parse(userSignupFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearer_token'
        },
        body: jsonEncode({'username': username, 'email': email, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('Registration successful: ${data['message']}');
        return true;
      } else {
        final error = jsonDecode(response.body);
        print('Registration failed: ${error['error']}');
        return false;
      }
    } catch (e) {
      print('An unexpected error occurred during registration: $e');
      return false;
    }
  }

  void UpdateUserModel(context, data)
  {
    Provider.of<UserModel>(context, listen: false).setUser(
      id: data['id'],
      email: data['email'],
      name: data['name'],
    );
  }

  Future<bool> userLogout(context) async {
    // Implement logout logic if you're managing sessions or tokens
    // For example, clear stored tokens or user data
    Provider.of<UserModel>(context, listen: false).clearUser();
    return true;
  }
}
