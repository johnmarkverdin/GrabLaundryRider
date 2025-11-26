import 'package:flutter/material.dart';
import 'supabase_config.dart';
import 'pages/auth_rider_page.dart';   // make sure this path & file name are correct
import 'pages/rider_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const RiderApp());
}

class RiderApp extends StatefulWidget {
  const RiderApp({Key? key}) : super(key: key);

  @override
  State<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> {
  bool _checkingSession = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();

    // listen for login/logout
    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      setState(() {
        _loggedIn = session != null;
      });
    });
  }

  void _checkSession() {
    final session = supabase.auth.currentSession;
    setState(() {
      _loggedIn = session != null;
      _checkingSession = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'GrabLaundry Rider',
      theme: ThemeData(primarySwatch: Colors.green),
      // ✅ show Auth when NOT logged in, Home when logged in
      home: _loggedIn ? const RiderHomePage() : const RiderAuthPage(),
    );
  }
}
