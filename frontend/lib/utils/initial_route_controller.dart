import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:imgrep/pages/get_started.dart';
import 'package:imgrep/pages/splashscreen.dart';

class InitialRouteController extends StatefulWidget {
  const InitialRouteController({super.key});

  @override
  // ignore: library_private_types_in_public_api
  InitialRouteControllerState createState() => InitialRouteControllerState();
}

class InitialRouteControllerState extends State<InitialRouteController> {
  bool _seenGetStarted = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFirstSeen();
    setState(() => _isLoading = false);
  }

  Future<void> _checkFirstSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seenGetStarted') ?? false;
    if (!seen) await prefs.setBool('seenGetStarted', true);

    setState(() {
      _seenGetStarted = seen;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _seenGetStarted ? SplashScreen() : Getstarted();
  }
}
