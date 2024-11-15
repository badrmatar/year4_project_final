import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import '../services/auth_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // final AuthService _authService = AuthService();
  final SupabaseClient _supabase = Supabase.instance.client;
  String _userEmail = '';
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? 'No Email';
        _userId = user.id;
      });
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _handleLogout() async {
    // await _authService.userLogout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: _userEmail.isNotEmpty
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Welcome, $_userEmail!',
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            // Add more widgets here as needed
          ],
        )
            : const CircularProgressIndicator(),
      ),
    );
  }
}