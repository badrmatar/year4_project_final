import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:year4_project/services/auth_service.dart';
import 'package:year4_project/services/analytics_service.dart';
import 'package:year4_project/models/user.dart';
import 'package:year4_project/pages/home_page.dart';
import 'package:year4_project/pages/login_page.dart';
import 'package:year4_project/pages/signup_page.dart';
import 'package:year4_project/pages/waiting_room.dart';
import 'package:year4_project/pages/challenges_page.dart';
import 'package:year4_project/pages/run_loading_page.dart';
import 'package:year4_project/pages/duo_active_run_page.dart';
import 'package:year4_project/pages/league_room_page.dart';
import 'package:year4_project/pages/journey_type_page.dart';
import 'package:year4_project/pages/duo_waiting_room_page.dart';
import 'package:year4_project/services/team_service.dart';
import 'package:year4_project/pages/history_page.dart';
import 'package:year4_project/analytics_route_observer.dart';
// Import Smartlook
import 'package:flutter_smartlook/flutter_smartlook.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
}

Future<void> requestLocationPermission() async {
  try {
    // First, check if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services disabled. Cannot request permission.');
      return;
    }

    if (Platform.isIOS) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied on iOS');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        print('Location permissions permanently denied on iOS, guide user to settings');
        return;
      }
    } else {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions denied');
          return;
        }
      }
    }

    // Test location access.
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      print(
          'Current location: ${position.latitude}, ${position.longitude}, accuracy: ${position.accuracy}m');
    } catch (e) {
      print('Error getting current position: $e');
    }
  } catch (e) {
    print('Error requesting location permission: $e');
  }
}

Future<void> initPosthog() async {
  try {
    // Create a configuration object
    final config = PostHogConfig('phc_uiuWH9NvkviwjtUsHRwkc9qgXvsWwlobSFgpbe9lRnF') // Replace with your actual API key
      ..debug = true // Set to false in production
      ..captureApplicationLifecycleEvents = true
      ..host = 'https://app.posthog.com'; // Or 'https://eu.i.posthog.com' for EU region

    // Initialize PostHog with the config
    await Posthog().setup(config);

    // Log a test event to verify setup
    await Posthog().capture(
      eventName: 'app_initialized',
      properties: {
        'timestamp': DateTime.now().toIso8601String(),
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
      },
    );

    print('PostHog initialized with test event');
  } catch (e) {
    print('Error initializing PostHog: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await initSupabase();
  await initPosthog();

  // Request location permissions early.
  await requestLocationPermission();

  final authService = AuthService();
  final isAuthenticated = await authService.checkAuthStatus();

  // Create initial UserModel.
  UserModel initialUserModel = UserModel(id: 0, email: '', name: '');

  // If authenticated, restore user session.
  if (isAuthenticated) {
    final userData = await authService.restoreUserSession();
    if (userData != null) {
      initialUserModel = UserModel(
        id: userData['id'],
        email: userData['email'],
        name: userData['name'],
      );

      // Identify the user in PostHog
      await AnalyticsService().client.identifyUser(
        userId: userData['id'].toString(),
        email: userData['email'],
        role: 'user',
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

class MyApp extends StatefulWidget {
  final String initialRoute;
  const MyApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _routeObserver = AnalyticsRouteObserver();
  final Smartlook smartlook = Smartlook.instance;

  @override
  void initState() {
    super.initState();
    // Initialize Smartlook.
    smartlook.start();
    smartlook.preferences.setProjectKey('5e6af6d7c885ec62a1814ea8ed55fcafc2fa91d6'); // Replace with your actual project key.
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserModel>(context);
    _checkUserTeam(user);
    return SmartlookRecordingWidget(
      child: MaterialApp(
        title: 'Running App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        navigatorObservers: [_routeObserver],
        initialRoute: widget.initialRoute,
        routes: {
          '/': (context) => const HomePage(),
          '/home': (context) => const HomePage(),
          '/login': (context) => const LoginPage(),
          '/signup': (context) => const SignUpPage(),
          '/waiting_room': (context) => WaitingRoomScreen(userId: user.id),
          '/challenges': (context) => const ChallengesPage(),
          '/journey_type': (context) => const JourneyTypePage(),
          '/duo_waiting_room': (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return DuoWaitingRoom(teamChallengeId: args['team_challenge_id'] as int);
          },
          '/run_loading': (context) => const RunLoadingPage(journeyType: 'solo', challengeId: 0),
          '/league_room': (context) => LeagueRoomPage(userId: user.id),
          '/history': (context) => const HistoryPage(),
          '/duo_active_run': (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return DuoActiveRunPage(challengeId: args['team_challenge_id'] as int);
          },
        },
      ),
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