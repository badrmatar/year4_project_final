import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:year4_project/services/auth_service.dart';

import 'package:year4_project/models/user.dart';
import 'package:year4_project/pages/home_page.dart';
import 'package:year4_project/pages/login_page.dart';
import 'package:year4_project/pages/signup_page.dart';
import 'package:year4_project/pages/waiting_room.dart';
import 'package:year4_project/pages/challenges_page.dart';
import 'package:year4_project/pages/active_run_page.dart';
import 'package:year4_project/pages/duo_active_run_page.dart';
import 'package:year4_project/pages/league_room_page.dart';
import 'package:year4_project/pages/journey_type_page.dart';
import 'package:year4_project/pages/duo_waiting_room_page.dart';
import 'package:year4_project/services/team_service.dart';
import 'package:year4_project/pages/history_page.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
}

Future<void> requestLocationPermission() async {
  try {
    // First check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled, show dialog to the user
      print('Location services disabled. Cannot request permission.');
      return;
    }

    // Special handling for iOS
    if (Platform.isIOS) {
      // For iOS, we need to be more explicit about the permission request
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Request location permission with more explicit messaging
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied on iOS');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Show a dialog directing user to settings
        print('Location permissions permanently denied on iOS, guide user to settings');
        return;
      }
    } else {
      // Original Android code path
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied');
          return;
        }
      }
    }

    // Test location access with a shorter timeout for iOS
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      print('Current location: ${position.latitude}, ${position.longitude}, accuracy: ${position.accuracy}m');
    } catch (e) {
      print('Error getting current position: $e');
    }
  } catch (e) {
    print('Error requesting location permission: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await initSupabase();

  // Request location permissions early in the app lifecycle
  await requestLocationPermission();

  final authService = AuthService();
  final isAuthenticated = await authService.checkAuthStatus();

  // Create initial UserModel
  UserModel initialUserModel = UserModel(id: 0, email: '', name: '');

  // If authenticated, try to restore user data
  if (isAuthenticated) {
    final userData = await authService.restoreUserSession();
    if (userData != null) {
      initialUserModel = UserModel(
        id: userData['id'],
        email: userData['email'],
        name: userData['name'],
      );
    }
  }

  final initialRoute = isAuthenticated ? '/home' : '/login';

  runApp(
    ChangeNotifierProvider(
      create: (_) => initialUserModel,
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserModel>(context);

    _checkUserTeam(user);

    return MaterialApp(
      title: 'Running App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const HomePage(),
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
        '/waiting_room': (context) => WaitingRoomScreen(userId: user.id),
        '/challenges': (context) => const ChallengesPage(),
        '/journey_type': (context) => const JourneyTypePage(),
        '/duo_waiting_room': (context) {
          final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return DuoWaitingRoom(teamChallengeId: args['team_challenge_id'] as int);
        },
        '/active_run': (context) {
          final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          if (args['journey_type'] == 'duo') {
            return DuoActiveRunPage(challengeId: args['team_challenge_id'] as int);
          }
          return ActiveRunPage(
            journeyType: 'solo',
            challengeId: args['challenge_id'] as int,
          );
        },
        '/league_room': (context) => LeagueRoomPage(userId: user.id),
        '/history': (context) => const HistoryPage(),
      },
    );
  }

  Future<void> _checkUserTeam(UserModel user) async {
    if (user.id == 0) return;
    final teamService = TeamService();
    final teamId = await teamService.fetchUserTeamId(user.id);
    if (teamId != null) {
      print('User ${user.id} belongs to team ID: $teamId');
    } else {
      print('User ${user.id} does not belong to any active team.');
    }
  }
}