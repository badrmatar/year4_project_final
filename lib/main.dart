import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';



import 'pages/login_page.dart';
import 'pages/home_page.dart';


void InitSupaBase() async
{
  await Supabase.initialize(
    url: 'https://ywhjlgvtjywhacgqtzqh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl3aGpsZ3Z0anl3aGFjZ3F0enFoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzA5Mjc5MTQsImV4cCI6MjA0NjUwMzkxNH0.46psoHtC8Z7E_Mxd8eGY0kNGbeDcRqAsucgRrBlzaxY',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  InitSupaBase();
  runApp(const MyApp());
}



class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // Determine the initial route based on authentication state
  String get initialRoute {
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? '/home' : '/login';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Supabase App',
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        // Add other routes here
      },
    );
  }
}