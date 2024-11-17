// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/user_model.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'https://ywhjlgvtjywhacgqtzqh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl3aGpsZ3Z0anl3aGFjZ3F0enFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzA5Mjc5MTQsImV4cCI6MjA0NjUwMzkxNH0.46psoHtC8Z7E_Mxd8eGY0kNGbeDcRqAsucgRrBlzaxY',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(
    ChangeNotifierProvider(
      create: (_) => UserModel(id: 0, email: '', name: ''),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Supabase App',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}
