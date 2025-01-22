// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserModel>(context);
    // If user.id == 0 => user not logged in. If your code uses that check
    // for showing different content, ensure you handle that logic.

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
            const SizedBox(height: 16),
            // Add this button to navigate to the ActiveRunPage
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/active_run');
              },
              child: const Text('Start Run'),
            ),
          ],
        ),
      ),
    );
  }
}
