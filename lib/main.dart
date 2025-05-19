import 'package:esp/screens/login_page.dart';
import 'package:esp/service.dart';
import 'package:esp/screens/splash_screen.dart';
import 'package:esp/screens/configuration_page.dart';
import 'package:esp/screens/device_config_landing.dart';
import 'package:esp/screens/ac_customization_page.dart';
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
      title: 'IR-Blaster App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      // Define the named routes
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => LoginPage(),
        '/home': (context) => const HomePage(),
        // '/config': (context) => const ConfigurationPage(),
        '/landing': (context) => const LandingPage(),
        '/customization': (context) => const AcCustomizationPage(),
      },
    );
  }
}