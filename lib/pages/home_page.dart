// lib/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    // Example: Check if user is already logged in
    // You might have a method to verify authentication status
    // For simplicity, assuming user data is already in Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserModel>(context, listen: false);
      if (user.id == 0) {
        // Navigate to Login Page if not logged in
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        // Stay on Home Page
        // Optionally, fetch additional user data if needed
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/waiting_room');
              },
              child: const Text('Go to Waiting Room'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/challenges');
              },
              child: const Text('View Challenges'),
            ),
          ],
        ),
      ),
    );
  }

}