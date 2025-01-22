// lib/services/auth_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/user.dart';

class AuthService {
  final String userLoginFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_login';
  final String userSignupFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_signup';
  final String userLogoutFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_logout';
  final String bearerToken = dotenv.env['BEARER_TOKEN']!;

  Future<bool> userLogin(BuildContext context, String email, String password) async {
    try {
      print('Sending login request with Email: $email'); // Avoid logging passwords in production
      final response = await http.post(
        Uri.parse(userLoginFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('Login successful: ${data['message']}');
        _updateUserModel(context, data);
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
      print('Sending registration request for $email'); // Avoid logging sensitive data in production
      final response = await http.post(
        Uri.parse(userSignupFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
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

  Future<bool> userLogout(BuildContext context, int userId) async {
    try {
      print('Sending logout request for user ID: $userId');
      final response = await http.post(
        Uri.parse(userLogoutFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $bearerToken',
        },
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Logout successful: ${data['message']}');
        _clearUserModel(context);
        return true;
      } else {
        final error = jsonDecode(response.body);
        print('Logout failed: ${error['error']}');
        return false;
      }
    } catch (e) {
      print('An unexpected error occurred during logout: $e');
      return false;
    }
  }

  void _updateUserModel(BuildContext context, Map<String, dynamic> data) {
    Provider.of<UserModel>(context, listen: false).setUser(
      id: data['id'],
      email: data['email'],
      name: data['name'],
    );
  }

  void _clearUserModel(BuildContext context) {
    Provider.of<UserModel>(context, listen: false).clearUser();
  }
}
