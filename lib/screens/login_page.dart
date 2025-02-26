// login_page.dart
import 'dart:ui';
import 'package:esp/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

class LoginPage extends StatelessWidget {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  LoginPage({super.key});

  Future<void> _handleLogin(BuildContext context) async {
    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();

    // Allowed credentials (In a real app, replace this with backend validation)
    const allowedUsers = {
      "pmel@tech.com": "123",
      "demo@sustainabyte.com": "123",
    };

    // Check if the provided credentials are valid
    if (allowedUsers[email] == password) {
      // Generate a mock token (in a real app, this would come from the backend)
      String mockToken = 'mock_token_${DateTime.now().millisecondsSinceEpoch}';

      // Save authentication details
      await _authService.saveAuthDetails(email, mockToken);

      // Navigate to home if the context is still valid
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      // Show an error dialog if the credentials are invalid
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Error"),
            content: const Text("Invalid credentials!"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rest of your existing build method remains the same
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: const Color.fromARGB(255, 13, 41, 64),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Column(
                  children: <Widget>[
                    // Your existing header section...
                    Expanded(
                      flex: 3,
                      child: Stack(
                        children: <Widget>[
                          Positioned(
                            top: 0,
                            right: 300.0,
                            child: FadeInUp(
                              duration: const Duration(seconds: 1),
                              child: const Text("FusionByte Logo Here"),
                            ),
                          ),
                          Positioned(
                            top: 80,
                            left: MediaQuery.of(context).size.width / 2 - 100,
                            child: const Text(
                              "FUSIONBYTE",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Color.fromRGBO(84, 196, 86, 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Login Form Section
                    Expanded(
                      flex: 9,
                      child: Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Column(
                          children: <Widget>[
                            // Your existing login form widgets...
                            Container(
                              width: 180.0,
                              height: 180.0,
                              decoration: const BoxDecoration(
                                image: DecorationImage(
                                  image: AssetImage('assets/images/welding.jpg'),
                                  fit: BoxFit.cover,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color.fromRGBO(172, 173, 173, 1),
                                    blurRadius: 20.0,
                                    offset: Offset(0, 3),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            const Text(
                              "LOGIN",
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 30),

                            // Input Fields
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color.fromRGBO(84, 196, 86, 1),
                                ),
                              ),
                              child: Column(
                                children: <Widget>[
                                  TextField(
                                    controller: emailController,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: "Email or Phone number",
                                      hintStyle: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ),
                                  const Divider(color: Color.fromRGBO(84, 196, 86, 1)),
                                  TextField(
                                    controller: passwordController,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: "Password",
                                      hintStyle: TextStyle(color: Colors.grey[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 50),

                            // Updated Login Button with new handler
                            GestureDetector(
                              onTap: () => _handleLogin(context),
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: const Color.fromRGBO(84, 196, 86, 1),
                                ),
                                child: const Center(
                                  child: Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}