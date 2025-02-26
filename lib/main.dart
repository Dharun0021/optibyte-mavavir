import 'package:esp/screens/login_page.dart';
import 'package:esp/service.dart';
import 'package:esp/screens/splash_screen.dart';
import 'package:flutter/material.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FusionByte App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // Define the named routes
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => LoginPage(),
        '/home': (context) => const HomePage(), // You'll need to create this
      },
    );
  }
}