// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:year4_project/pages/map_page.dart';
import 'package:year4_project/pages/signup_page.dart';
import 'package:year4_project/pages/waiting_room.dart';
import 'models/user.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
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
    final user = Provider.of<UserModel>(context);
    return MaterialApp(
      title: 'Running App',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/waiting_room': (context) => WaitingRoomScreen(userId: user.id,),
      },
    );
  }
}
