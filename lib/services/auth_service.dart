import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';

class AuthService {
  final String userLoginFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_login';
  final String userSignupFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_signup';
  final String userLogoutFunctionUrl =
      'https://ywhjlgvtjywhacgqtzqh.supabase.co/functions/v1/user_logout';
  final String bearerToken = dotenv.env['BEARER_TOKEN']!;

  final storage = const FlutterSecureStorage();

  Future<void> _storeUserData(Map<String, dynamic> userData) async {
    await storage.write(key: 'user_id', value: userData['id'].toString());
    await storage.write(key: 'user_email', value: userData['email'].toString());
    await storage.write(key: 'user_name', value: userData['name'].toString());
  }

  Future<Map<String, dynamic>?> _getUserData() async {
    final userId = await storage.read(key: 'user_id');
    final userEmail = await storage.read(key: 'user_email');
    final userName = await storage.read(key: 'user_name');

    if (userId != null && userEmail != null && userName != null) {
      return {
        'id': int.parse(userId),
        'email': userEmail,
        'name': userName,
      };
    }
    return null;
  }

  Future<bool> userLogin(BuildContext context, String email, String password) async {
    try {
      print('Sending login request with Email: $email');
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
        print('Full response data: $data');

        await _storeUserData(data);
        print('User data stored successfully');

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
      print('Sending registration request for $email');
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
        await storage.deleteAll();
        print('User data cleared from storage');
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

  Future<bool> checkAuthStatus() async {
    final userData = await _getUserData();
    print('Checking auth status...');
    print('User data exists: ${userData != null}');
    if (userData != null) {
      print('User ID: ${userData['id']}');
      print('User Email: ${userData['email']}');
    }
    return userData != null;
  }

  Future<Map<String, dynamic>?> restoreUserSession() async {
    try {
      final userData = await _getUserData();
      if (userData != null) {
        print('Session restored for user: ${userData['name']}');
        return userData;
      }
      return null;
    } catch (e) {
      print('Error restoring session: $e');
      return null;
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