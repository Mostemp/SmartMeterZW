import 'package:vibration/vibration.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<bool> globalDarkMode = ValueNotifier(true);

Color get kBg => globalDarkMode.value ? const Color(0xFF0A0E1A) : Colors.grey[100]!;
Color get kCard => globalDarkMode.value ? const Color(0xFF111827) : Colors.white;
Color get kText => globalDarkMode.value ? Colors.white : Colors.black87;
Color get kSubText => globalDarkMode.value ? Colors.grey[400]! : Colors.black54;
Color get kDivider => globalDarkMode.value ? Colors.white10 : Colors.black12;

// Original constants
const String BASE_URL = 'http://192.168.137.1:5000';
const Color kGreen = Color(0xFF00D4AA);
const Color kEcoGreen = Color(0xFF4CAF50);

String currentMeterNumber = '1234567890';
String currentUsername = 'admin';

void main() => runApp(const SmartMeterApp());

// ─── Models ───────────────────────────────────────────────
class MeterStatus {
  final double unitBalance;
  final double consumptionKw;
  final bool tamperAlert;
  final double voltage;
  final String status;
  MeterStatus({
    required this.unitBalance,
    required this.consumptionKw,
    required this.tamperAlert,
    required this.voltage,
    required this.status,
  });
  factory MeterStatus.fromJson(Map<String, dynamic> j) => MeterStatus(
    unitBalance: (j['unit_balance'] as num).toDouble(),
    consumptionKw: (j['consumption_kw'] as num).toDouble(),
    tamperAlert: j['tamper_alert'] as bool,
    voltage: (j['voltage'] as num).toDouble(),
    status: j['status'] as String,
  );
}

class AppNotification {
  final String title;
  final String body;
  final DateTime time;
  final IconData icon;
  final Color color;
  AppNotification({
    required this.title,
    required this.body,
    required this.time,
    required this.icon,
    required this.color,
  });
}

// ─── Global Notification Store ────────────────────────────
final List<AppNotification> globalNotifications = [
  AppNotification(
    title: 'Welcome to SmartMeter ZW',
    body: 'Your meter is connected and monitoring has started.',
    time: DateTime.now().subtract(const Duration(hours: 2)),
    icon: Icons.check_circle,
    color: kGreen,
  ),
];

// ─── App Root ─────────────────────────────────────────────
class SmartMeterApp extends StatelessWidget {
  const SmartMeterApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: globalDarkMode,
        builder: (context, isDark, child) {
          return MaterialApp(
            title: 'SmartMeter ZW',
            debugShowCheckedModeBanner: false,
            theme: isDark
                ? ThemeData.dark().copyWith(
                    scaffoldBackgroundColor: kBg,
                    colorScheme: const ColorScheme.dark(primary: kGreen),
                  )
                : ThemeData.light().copyWith(
                    scaffoldBackgroundColor: kBg,
                    colorScheme: const ColorScheme.light(primary: kGreen),
                  ),
            home: const LoginScreen(),
          );
        },
      );
}

// ════════════════════════════════════════════════════════════
// 1. LOGIN SCREEN
// ════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _meterCtrl = TextEditingController();
  
  // Registration controllers
  final _regUsernameCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regMeterCtrl = TextEditingController();
  final _regAddressCtrl = TextEditingController();
  final _regConfirmPasswordCtrl = TextEditingController();

  bool _rememberMe = true;
  bool _hasSavedCredentials = false;
  String _savedUsername = '';
  String _savedMeterNumber = '';
  bool _isRegistering = false;
  bool _loading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(_shakeController);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _meterCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regMeterCtrl.dispose();
    _regAddressCtrl.dispose();
    _regConfirmPasswordCtrl.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    final user = prefs.getString('saved_username') ?? '';
    final meter = prefs.getString('saved_meter_number') ?? '';
    
    if (remember && user.isNotEmpty && meter.isNotEmpty) {
      setState(() {
        _rememberMe = true;
        _hasSavedCredentials = true;
        _savedUsername = user;
        _savedMeterNumber = meter;
      });
    }
  }

  Future<void> _saveCredentials(String username, String meterNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
    if (_rememberMe) {
      await prefs.setString('saved_username', username);
      await prefs.setString('saved_meter_number', meterNumber);
    } else {
      await prefs.remove('saved_username');
      await prefs.remove('saved_meter_number');
    }
  }

  Future<void> _clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_meter_number');
    await prefs.setBool('remember_me', false);
    setState(() {
      _hasSavedCredentials = false;
      _rememberMe = false;
      _savedUsername = '';
      _savedMeterNumber = '';
      _usernameCtrl.clear();
      _meterCtrl.clear();
      _passwordCtrl.clear();
    });
  }

  Future<void> _login() async {
    final username = _hasSavedCredentials ? _savedUsername : _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Username and password are required.');
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 20); } catch (_) {}
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          currentUsername = data['user']['username'];
          currentMeterNumber = data['user']['meter_number'];
          
          await _saveCredentials(currentUsername, currentMeterNumber);
          
          try { Vibration.vibrate(duration: 50); } catch (_) {}
          if (mounted) {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 600),
              ),
            );
          }
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          _errorMessage = data['message'] ?? 'Invalid login details.';
          _loading = false;
        });
        _shakeController.forward(from: 0.0);
        try { Vibration.vibrate(duration: 200); } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot reach authentication server.';
        _loading = false;
      });
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 200); } catch (_) {}
    }
  }

  Future<void> _register() async {
    final username = _regUsernameCtrl.text.trim();
    final meter = _regMeterCtrl.text.trim();
    final password = _regPasswordCtrl.text;
    final address = _regAddressCtrl.text.trim();
    final confirmPassword = _regConfirmPasswordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Username and password are required.');
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 20); } catch (_) {}
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 20); } catch (_) {}
      return;
    }

    final hasLetters = password.contains(RegExp(r'[a-zA-Z]'));
    final hasNumbers = password.contains(RegExp(r'[0-9]'));
    if (!hasLetters || !hasNumbers) {
      setState(() => _errorMessage = 'Password must be a mixture of numbers and letters.');
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 20); } catch (_) {}
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'meter_number': meter,
          'address': address,
        }),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          try { Vibration.vibrate(duration: 100); } catch (_) {}
          setState(() {
            _isRegistering = false;
            _usernameCtrl.text = username;
            _meterCtrl.text = meter;
            _passwordCtrl.clear();
            _regPasswordCtrl.clear();
            _regConfirmPasswordCtrl.clear();
            _regAddressCtrl.clear();
            _errorMessage = '';
            _loading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: kEcoGreen,
                content: Text(data['message'] ?? 'Registration successful! Pls login.'),
              ),
            );
          }
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          _errorMessage = data['message'] ?? 'Registration failed.';
          _loading = false;
        });
        _shakeController.forward(from: 0.0);
        try { Vibration.vibrate(duration: 200); } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Cannot reach authentication server.';
        _loading = false;
      });
      _shakeController.forward(from: 0.0);
      try { Vibration.vibrate(duration: 200); } catch (_) {}
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  Widget _buildGlassField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.01),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: TextStyle(color: kText, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: kSubText, fontSize: 13),
          prefixIcon: Icon(icon, color: kGreen, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.04),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kGreen, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // Background glows
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kGreen.withOpacity(0.1),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.transparent),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_shakeAnimation.value, 0),
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Bolt neon logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: kGreen.withOpacity(0.6), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: kGreen.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(Icons.bolt, color: kGreen, size: 40),
                      ),
                      SizedBox(height: 20),
                      
                      Text(
                        _getGreeting(),
                        style: TextStyle(
                          color: kSubText,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'SmartMeter ZW',
                        style: TextStyle(
                          color: kText,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 30),

                      // Glassmorphic Input Card
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.07)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_hasSavedCredentials && !_isRegistering) ...[
                              // Saved credentials welcome-back flow
                              Column(
                                children: [
                                  SizedBox(height: 8),
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: kGreen.withOpacity(0.15),
                                    child: Icon(Icons.person, color: kGreen, size: 30),
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'Welcome Back,',
                                    style: TextStyle(color: kSubText, fontSize: 13),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    _savedUsername,
                                    style: TextStyle(
                                      color: kText,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Meter: $_savedMeterNumber',
                                    style: TextStyle(color: kGreen.withOpacity(0.8), fontSize: 12),
                                  ),
                                  SizedBox(height: 24),
                                  _buildGlassField(
                                    controller: _passwordCtrl,
                                    label: 'Password',
                                    icon: Icons.lock,
                                    obscureText: _obscurePassword,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                        color: Colors.grey,
                                        size: 18,
                                      ),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _clearSavedCredentials,
                                      child: Text(
                                        'Log in with another account',
                                        style: TextStyle(color: Colors.grey, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              // Tab switch Login / Register
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _isRegistering = false;
                                        _errorMessage = '';
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: !_isRegistering ? kGreen : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'LOGIN',
                                            style: TextStyle(
                                              color: !_isRegistering ? kText : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _isRegistering = true;
                                        _errorMessage = '';
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: _isRegistering ? kGreen : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'REGISTER',
                                            style: TextStyle(
                                              color: _isRegistering ? kText : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 24),
                              
                              if (!_isRegistering) ...[
                                // Full Login fields
                                _buildGlassField(
                                  controller: _usernameCtrl,
                                  label: 'Username',
                                  icon: Icons.person_outline,
                                ),
                                _buildGlassField(
                                  controller: _passwordCtrl,
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                // Remember Me
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor: kGreen,
                                        checkColor: Colors.black,
                                        onChanged: (v) => setState(() => _rememberMe = v ?? true),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Remember Login Details',
                                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                              ] else ...[
                                // Register fields
                                _buildGlassField(
                                  controller: _regUsernameCtrl,
                                  label: 'Register Username',
                                  icon: Icons.person_add_alt_1_outlined,
                                ),
                                _buildGlassField(
                                  controller: _regAddressCtrl,
                                  label: 'Address',
                                  icon: Icons.location_on_outlined,
                                ),
                                _buildGlassField(
                                  controller: _regMeterCtrl,
                                  label: 'Register Meter Number (Optional)',
                                  icon: Icons.electric_meter_outlined,
                                  keyboardType: TextInputType.number,
                                ),
                                _buildGlassField(
                                  controller: _regPasswordCtrl,
                                  label: 'Register Password',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                _buildGlassField(
                                  controller: _regConfirmPasswordCtrl,
                                  label: 'Confirm Password',
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                              ],
                            ],
                            
                            // Error text
                            if (_errorMessage.isNotEmpty) ...[
                              SizedBox(height: 12),
                              Text(
                                _errorMessage,
                                style: TextStyle(color: Colors.redAccent, fontSize: 12),
                              ),
                            ],
                            SizedBox(height: 20),
                            
                            // Submit button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _loading
                                    ? null
                                    : (_isRegistering ? _register : _login),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kGreen,
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor: kGreen.withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 5,
                                  shadowColor: kGreen.withOpacity(0.3),
                                ),
                                child: _loading
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.black,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        _isRegistering ? 'CREATE ACCOUNT' : 'LOG IN',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 24),
                      Text(
                        'Demo: admin / 1234 / 1234567890',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11, letterSpacing: 0.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 2. MAIN SCREEN
// ════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  Timer? _tamperTimer;
  bool _lastTamper = false;
  final AudioPlayer _tamperPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Poll for tamper globally - works on any tab
    _tamperTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkTamper());
    _checkTamper(); // check immediately on launch
  }

  @override
  void dispose() {
    _tamperTimer?.cancel();
    _tamperPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkTamper() async {
    try {
      final res = await http
          .get(Uri.parse('$BASE_URL/api/status'), headers: {'X-Meter-Number': currentMeterNumber})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final s = MeterStatus.fromJson(jsonDecode(res.body));
        if (s.tamperAlert && !_lastTamper) {
          // Tamper just triggered
          try {
            Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
          } catch (vibeErr) {
            debugPrint('Vibration failed: $vibeErr');
          }

          try {
            _tamperPlayer.setReleaseMode(ReleaseMode.loop);
            _tamperPlayer.play(AssetSource('sounds/alarm.mp3'));
          } catch (audioErr) {
            debugPrint('Audio failed: $audioErr');
          }

          if (mounted) setState(() {});
          globalNotifications.insert(
            0,
            AppNotification(
              title: 'TAMPER ALERT',
              body: 'Unauthorized tampering detected on your meter!',
              time: DateTime.now(),
              icon: Icons.warning_amber,
              color: Colors.red,
            ),
          );
        } else if (!s.tamperAlert && _lastTamper) {
          // Tamper cleared
          try {
            _tamperPlayer.stop();
          } catch (audioStopErr) {
            debugPrint('Audio stop failed: $audioStopErr');
          }
        }
        _lastTamper = s.tamperAlert;
      }
    } catch (e) {
      debugPrint('Error polling status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isGuest = currentMeterNumber.startsWith('GUEST');
    final pages = isGuest
        ? [
            const DashboardPage(),
            const TopUpPage(),
            const ChatbotPage(),
          ]
        : [
            const DashboardPage(),
            const HistoryPage(),
            const TopUpPage(),
            NotificationsPage(onUpdate: () => setState(() {})),
            const ChatbotPage(),
            const SettingsPage(),
          ];
    final unread = globalNotifications.length;
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: kCard,
        indicatorColor: kGreen.withOpacity(0.2),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: isGuest
            ? [
                const NavigationDestination(
                  icon: Icon(Icons.bolt),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.add_card),
                  label: 'Top Up',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.support_agent),
                  label: 'Chat Help',
                ),
              ]
            : [
                const NavigationDestination(
                  icon: Icon(Icons.bolt),
                  label: 'Dashboard',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.bar_chart),
                  label: 'History',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.add_card),
                  label: 'Top Up',
                ),
                NavigationDestination(
                  icon: Badge(
                    label: Text('$unread'),
                    isLabelVisible: unread > 0,
                    child: Icon(Icons.notifications),
                  ),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.support_agent),
                  label: 'Chat Help',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 3. DASHBOARD
// ════════════════════════════════════════════════════════════
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  MeterStatus? _status;
  bool _loading = true;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse('$BASE_URL/api/status'), headers: {'X-Meter-Number': currentMeterNumber})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final s = MeterStatus.fromJson(jsonDecode(res.body));
        if (s.unitBalance < 5 &&
            (_status == null || _status!.unitBalance >= 5)) {
          globalNotifications.insert(
            0,
            AppNotification(
              title: 'Low Balance Warning',
              body: 'Your balance is below 5 Units. Please top up soon.',
              time: DateTime.now(),
              icon: Icons.battery_alert,
              color: Colors.orange,
            ),
          );
        }
        if (mounted)
          setState(() {
            _status = s;
            _loading = false;
            _error = '';
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Cannot reach meter server';
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SmartMeter ZW',
                      style: TextStyle(
                        color: kGreen,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Live Dashboard',
                      style: TextStyle(color: kSubText, fontSize: 13),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MeterDetailsPage()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (_error.isEmpty ? kGreen : Colors.red).withOpacity(
                        0.15,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: _error.isEmpty ? kGreen : Colors.red,
                        ),
                        SizedBox(width: 5),
                        Text(
                          _error.isEmpty ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            color: _error.isEmpty ? kGreen : Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            if (currentMeterNumber.startsWith('GUEST'))
              _buildGuestDashboard()
            else if (_loading)
              const Center(child: CircularProgressIndicator(color: kGreen))
            else if (_error.isNotEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.red, size: 48),
                    SizedBox(height: 12),
                    Text(_error, style: TextStyle(color: Colors.red)),
                    SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _fetch,
                      child: Text('Retry'),
                    ),
                  ],
                ),
              )
            else ...[
              if (_status!.tamperAlert)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        '⚠️ TAMPER ALERT DETECTED',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildCard(
                label: 'Unit Balance',
                value: '${_status!.unitBalance.toStringAsFixed(2)} Units',
                icon: Icons.electric_bolt,
                color: _status!.unitBalance < 5 ? Colors.orange : kGreen,
                subtitle: _status!.status == 'LOW_BALANCE'
                    ? '⚠️ Low balance — top up soon!'
                    : 'Balance is healthy',
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildCard(
                      label: 'Consumption',
                      value: '${_status!.consumptionKw} kW',
                      icon: Icons.power,
                      color: Colors.blueAccent,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: _buildCard(
                      label: 'Voltage',
                      value: '${_status!.voltage} V',
                      icon: Icons.bolt,
                      color: Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MeterDetailsPage()),
                ),
                child: _buildCard(
                  label: 'Meter Details',
                  value: 'View Info →',
                  icon: Icons.info_outline,
                  color: Colors.tealAccent,
                  subtitle: 'Serial, tariff, account info',
                ),
              ),
              SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatbotPage()),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kGreen.withOpacity(0.3),
                        Colors.blueAccent.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kGreen.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy, color: kGreen, size: 30),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Assistant',
                            style: TextStyle(
                              color: kGreen,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Ask about your usage, tips & more',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: kGreen,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 10),
          Text(label, style: TextStyle(color: kSubText, fontSize: 12)),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuestDashboard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGreen.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: kGreen.withOpacity(0.1),
            child: Icon(Icons.support_agent_outlined, color: kGreen, size: 36),
          ),
          SizedBox(height: 20),
          Text(
            'Welcome Guest!',
            style: TextStyle(
              color: kText,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'You are logged in as a Guest User. No active meter is linked to this account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kSubText,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          SizedBox(height: 24),
          Divider(color: kDivider),
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: kGreen, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Buy prepaid electricity tokens for any user',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: kGreen, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Access the smart ZESA rule-based Chatbot',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          Text(
            'To purchase units, switch to the "Top Up" tab and enter the target meter number.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kGreen.withOpacity(0.8),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 24),
          Divider(color: kDivider),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              ),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Log Out of Guest Mode',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 4. HISTORY PAGE
// ════════════════════════════════════════════════════════════
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _analyzing = false;
  bool _showAdvice = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(Uri.parse('$BASE_URL/api/history'), headers: {'X-Meter-Number': currentMeterNumber});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['history'] as List;
        setState(() {
          _history = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxUnits = _history.isEmpty
        ? 1.0
        : _history
              .map((e) => (e['Units'] as num).toDouble())
              .reduce((a, b) => a > b ? a : b);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage History',
              style: TextStyle(
                color: kGreen,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Last 7 days consumption (Units)',
              style: TextStyle(color: kSubText, fontSize: 13),
            ),
            SizedBox(height: 30),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: kGreen))
            else if (currentMeterNumber.startsWith('GUEST'))
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.grey[600], size: 48),
                      SizedBox(height: 16),
                      Text(
                        'No History in Guest Mode',
                        style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Track usage logs by registering with a physical meter.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (_history.isEmpty)
              const Center(
                child: Text(
                  'No history available',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else ...[
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 250,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: _history.map((d) {
                            final unitsValue = (d['Units'] as num).toDouble();
                            final heightFrac = unitsValue / maxUnits;
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${unitsValue.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    color: (globalDarkMode.value ? Colors.white70 : Colors.black87),
                                    fontSize: 10,
                                  ),
                                ),
                                SizedBox(height: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 600),
                                  width: 32,
                                  height: 180 * heightFrac,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [kGreen, kGreen.withOpacity(0.4)],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  d['day'],
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statItem(
                              'Total',
                              '${_history.fold(0.0, (s, e) => s + (e['Units'] as num).toDouble()).toStringAsFixed(1)} Units',
                            ),
                            _statItem(
                              'Average',
                              '${(_history.fold(0.0, (s, e) => s + (e['Units'] as num).toDouble()) / _history.length).toStringAsFixed(1)} Units/day',
                            ),
                            _statItem('Peak', '${maxUnits.toStringAsFixed(1)} Units'),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      _buildAiAdvisorSection(maxUnits),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAiAdvisorSection(double maxUnits) {
    if (currentMeterNumber.startsWith('GUEST')) return SizedBox();

    final totalUnits = _history.fold(0.0, (s, e) => s + (e['Units'] as num).toDouble());
    final avgUnits = _history.isEmpty ? 0.0 : totalUnits / _history.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _showAdvice ? kGreen.withOpacity(0.3) : (globalDarkMode.value ? kText : Colors.black).withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, color: kGreen, size: 24),
              SizedBox(width: 10),
              Text(
                'AI Energy Advisor',
                style: TextStyle(
                  color: kText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_showAdvice)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AI INSIGHTS',
                    style: TextStyle(
                      color: kGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12),
          if (!_showAdvice) ...[
            Text(
              'Get a personalized AI audit of your 7-day power profile and appliance advice.',
              style: TextStyle(color: kSubText, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _analyzing ? null : () async {
                  setState(() => _analyzing = true);
                  await Future.delayed(const Duration(milliseconds: 1800));
                  if (mounted) {
                    setState(() {
                      _analyzing = false;
                      _showAdvice = true;
                    });
                  }
                },
                icon: _analyzing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kText,
                        ),
                      )
                    : Icon(Icons.analytics_outlined, color: Colors.black),
                label: Text(
                  _analyzing ? 'Analyzing Consumption Patterns...' : 'Analyze Power with AI',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ] else ...[
            Text(
              'AI AUDIT REPORT & ENERGY COACH:',
              style: TextStyle(
                color: kGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 12),
            if (avgUnits > 15) ...[
              _adviceWarningCard(
                '⚠️ HIGH WEEKLY CONSUMPTION',
                'Your average daily usage is ${avgUnits.toStringAsFixed(1)} Units. Heavy heating appliances (geysers, stove, heaters) are running for too long.',
                Colors.orange,
              ),
            ] else ...[
              _adviceWarningCard(
                '🌱 ECO-FRIENDLY POWER PROFILE',
                'Excellent! Your average daily usage is ${avgUnits.toStringAsFixed(1)} Units. You are operating well within recommended residential energy saving limits.',
                kGreen,
              ),
            ],
            SizedBox(height: 12),
            _adviceWarningCard(
              '🍳 STOVE OVERCONSUMPTION DETECTED',
              'Stove & Oven detected consuming 35% of daily draft. Cooking during 5 PM - 8 PM ZESA dinner peaks is draining tokens fast. AI recommends using microwave or pressure cooker for quick meals to save up to 40% cooking energy.',
              Colors.blueAccent,
            ),
            SizedBox(height: 12),
            _adviceWarningCard(
              '🚿 GEYSER HEATING ADVICE',
              'Your water geyser timer overlaps with high Stage 2 loadshedding. Shift geyser heating exclusively to off-peak slots (10 PM to 5 AM) for 30% instant savings.',
              Colors.purpleAccent,
            ),
            SizedBox(height: 16),
            Divider(color: kDivider),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Estimated savings: \$${(avgUnits * 0.35 * 30 * 0.25).toStringAsFixed(2)} USD / month',
                  style: TextStyle(
                    color: (globalDarkMode.value ? Colors.white70 : Colors.black87),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showAdvice = false),
                  child: Text(
                    'Reset Audit',
                    style: TextStyle(color: Colors.grey, fontSize: 11, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _adviceWarningCard(String title, String body, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: (globalDarkMode.value ? Colors.white70 : Colors.black87),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          color: kGreen,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      Text(label, style: TextStyle(color: kSubText, fontSize: 11)),
    ],
  );
}

// ════════════════════════════════════════════════════════════
// 5. TOP UP PAGE
// ════════════════════════════════════════════════════════════
class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});
  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  int _selectedAmount = 5;
  String _selectedCurrency = 'USD';
  String _paymentMethod = 'ecocash'; // 'ecocash' | 'token' | 'paypal'
  final TextEditingController _phoneController = TextEditingController(text: '077');
  final TextEditingController _oneMoneyController = TextEditingController(text: '071');
  final TextEditingController _innbucksController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _meterController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (!currentMeterNumber.startsWith('GUEST')) {
      _meterController.text = currentMeterNumber;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _oneMoneyController.dispose();
    _innbucksController.dispose();
    _cardNumberController.dispose();
    _tokenController.dispose();
    _meterController.dispose();
    super.dispose();
  }

  Future<void> _initiatePayment() async {
    final phone = _phoneController.text.trim();
    final targetMeter = _meterController.text.trim();

    if (targetMeter.isEmpty) {
      _showEconetPopup(
        'Missing Meter',
        'Please enter a target prepaid meter number.',
        success: false,
      );
      return;
    }
    if (phone.length < 10) {
      _showEconetPopup(
        'Invalid Number',
        'Please enter a valid Econet number to proceed.',
        success: false,
      );
      return;
    }

    final double unitRate = _selectedCurrency == 'USD' ? 0.35 : 8.75;
    final String amountText = _selectedCurrency == 'USD' 
        ? '\$$_selectedAmount USD' 
        : 'ZiG $_selectedAmount';
    final double unitsToReceive = _selectedAmount / unitRate;

    setState(() => _loading = true);
    String targetUserName = 'Unknown';
    String targetAddress = 'Unknown';
    try {
      final res = await http.get(Uri.parse('$BASE_URL/api/meter_info/$targetMeter'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        targetUserName = data['username'] ?? 'Unknown';
        targetAddress = data['address'] ?? 'Unknown';
      } else {
        setState(() => _loading = false);
        _showEconetPopup(
          'Meter Not Found',
          'The meter number $targetMeter is not registered.',
          success: false,
        );
        return;
      }
    } catch (e) {
      setState(() => _loading = false);
      _showEconetPopup(
        'Connection Error',
        'Could not verify meter number.',
        success: false,
      );
      return;
    }
    setState(() => _loading = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Payment',
          style: TextStyle(color: kText, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow('Amount', amountText),
            _confirmRow('EcoCash No.', phone),
            _confirmRow(
              'Units',
              '${unitsToReceive.toStringAsFixed(2)} Units',
            ),
            _confirmRow('Meter', targetMeter),
            _confirmRow('Name', targetUserName),
            _confirmRow('Address', targetAddress),
            Divider(color: Colors.grey),
            Text(
              'By confirming, you authorise EcoCash to deduct this amount from your wallet.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kEcoGreen),
            child: Text('Confirm', style: TextStyle(color: kText)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final pinEntered = await _showEcocashPinDialog();
    if (pinEntered != true) return;

    setState(() => _loading = true);
    _showProcessingPopup();
    await Future.delayed(const Duration(seconds: 3));

    try {
      final endpoint = _selectedCurrency == 'USD' 
          ? '/api/topup/$_selectedAmount' 
          : '/api/topup_zig/$_selectedAmount';

      final res = await http.post(
        Uri.parse('$BASE_URL$endpoint'),
        headers: {'X-Meter-Number': targetMeter},
      );
      Navigator.of(context).pop();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final units = data['units_added'];
        final balance = data['new_balance'];

        final String payoutMessage = _selectedCurrency == 'USD'
            ? 'Confirmed. \$$_selectedAmount.00 paid to ZESA SmartMeter for meter $targetMeter. '
            : 'Confirmed. ZiG $_selectedAmount.00 paid to ZESA SmartMeter for meter $targetMeter. ';

        final String floatMessage = _selectedCurrency == 'USD'
            ? 'Float bal: \$${(50 - _selectedAmount).toStringAsFixed(2)}.'
            : 'Float bal: ZiG ${(1000 - _selectedAmount).toStringAsFixed(2)}.';

        _showEconetPopup(
          'EcoCash by Econet',
          payoutMessage +
              'Token: ${_generateToken()}. ' +
              '${units.toStringAsFixed(2)} Units added. ' +
              'New balance: ${balance.toStringAsFixed(2)} Units. ' +
              floatMessage,
          success: true,
        );
        globalNotifications.insert(
          0,
          AppNotification(
            title: 'Top-up Successful',
            body:
                '$amountText paid. +${units.toStringAsFixed(2)} Units added.',
            time: DateTime.now(),
            icon: Icons.add_circle,
            color: kGreen,
          ),
        );
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      if (mounted)
        _showEconetPopup(
          'Transaction Failed',
          'Unable to process payment. Please try again.',
          success: false,
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _generateToken() {
    final r = Random();
    return List.generate(20, (_) => r.nextInt(10).toString())
        .join()
        .replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)}-')
        .trimRight()
        .replaceAll(RegExp(r'-$'), '');
  }

  // ─── New Payment Flows ───────────────────────────────────────────
  Future<void> _initiateOneMoney() async {
    // Simulated OneMoney flow
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1)); // simulate check
    setState(() => _loading = false);
    
    final pinEntered = await _showSimulatedPinDialog('OneMoney PIN', Colors.orange);
    if (pinEntered != true) return;

    _processSimulatedPayment('OneMoney', Colors.orange, targetMeter);
  }

  Future<void> _initiateInnBucks() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _loading = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('InnBucks Payment', style: TextStyle(color: Colors.blue)),
        content: Text('Open your InnBucks app to authorize \$$_selectedAmount USD.', style: TextStyle(color: kText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: Text('I have authorized')),
        ],
      )
    );
    if (confirmed != true) return;
    _processSimulatedPayment('InnBucks', Colors.blue, targetMeter);
  }

  Future<void> _initiatePaynow() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2)); // Simulate redirect
    setState(() => _loading = false);
    _processSimulatedPayment('Paynow', Colors.purple, targetMeter);
  }

  Future<void> _initiateCardPayment() async {
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup('Missing Meter', 'Please enter a target prepaid meter number.', success: false);
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _loading = false);

    final pinEntered = await _showSimulatedPinDialog('Card PIN / OTP', Colors.indigo);
    if (pinEntered != true) return;

    _processSimulatedPayment('Visa/Mastercard', Colors.indigo, targetMeter);
  }

  Future<bool?> _showSimulatedPinDialog(String title, Color color) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        content: TextField(
          obscureText: true,
          keyboardType: TextInputType.number,
          style: TextStyle(color: kText),
          decoration: InputDecoration(labelText: 'Enter PIN / OTP', labelStyle: TextStyle(color: Colors.grey)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: color), child: Text('Submit')),
        ],
      )
    );
  }

  Future<void> _processSimulatedPayment(String method, Color color, String targetMeter) async {
    setState(() => _loading = true);
    _showProcessingPopup();
    await Future.delayed(const Duration(seconds: 2));

    try {
      final endpoint = _selectedCurrency == 'USD' ? '/api/topup/$_selectedAmount' : '/api/topup_zig/$_selectedAmount';
      final res = await http.post(Uri.parse('$BASE_URL$endpoint'), headers: {'X-Meter-Number': targetMeter});
      Navigator.of(context).pop(); // pop processing
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final units = data['units_added'];
        final balance = data['new_balance'];

        _showEconetPopup(
          '$method Payment Successful',
          '${_selectedCurrency == 'USD' ? '\$' : 'ZiG '}$_selectedAmount.00 paid via $method. Token: ${_generateToken()}. +${units.toStringAsFixed(2)} Units.',
          success: true,
        );
        globalNotifications.insert(0, AppNotification(
          title: '$method Top-up',
          body: '${_selectedCurrency == 'USD' ? '\$' : 'ZiG '}$_selectedAmount paid. +${units.toStringAsFixed(2)} Units.',
          time: DateTime.now(),
          icon: Icons.payment,
          color: color,
        ));
      }
    } catch (_) {
      Navigator.of(context).pop();
      _showEconetPopup('Failed', 'Payment failed.', success: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _redeemToken() async {
    final token = _tokenController.text.trim();
    final targetMeter = _meterController.text.trim();
    if (targetMeter.isEmpty) {
      _showEconetPopup(
        'Missing Meter',
        'Please enter a target prepaid meter number.',
        success: false,
      );
      return;
    }
    if (token.length < 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid ZESA token')));
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _loading = false);
    _showEconetPopup(
      'Token Redeemed',
      'ZESA Token accepted. 20.00 Units added to meter $targetMeter. Thank you.',
      success: true,
    );
  }

  Future<bool?> _showEcocashPinDialog() async {
    final List<String> pin = [];
    bool pinError = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPin) {
          void onKey(String digit) {
            if (pin.length >= 4) return;
            setPin(() {
              pin.add(digit);
              pinError = false;
            });
            if (pin.length == 4) {
              Future.delayed(
                const Duration(milliseconds: 300),
                () => Navigator.pop(ctx, true),
              );
            }
          }

          void onDelete() {
            if (pin.isNotEmpty) setPin(() => pin.removeLast());
          }

          final keys = [
            '1',
            '2',
            '3',
            '4',
            '5',
            '6',
            '7',
            '8',
            '9',
            '',
            '0',
            '⌫',
          ];
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A2332),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kEcoGreen, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: kEcoGreen,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.signal_cellular_alt,
                          color: kText,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'EcoCash by Econet',
                          style: TextStyle(
                            color: kText,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (globalDarkMode.value ? kText : Colors.black).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'SECURE',
                            style: TextStyle(
                              color: kText,
                              fontSize: 9,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kEcoGreen.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: kEcoGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.lock,
                            color: kEcoGreen,
                            size: 28,
                          ),
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Enter EcoCash PIN',
                          style: TextStyle(
                            color: kText,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Authorise payment of ${_selectedCurrency == "USD" ? "\$\$_selectedAmount USD" : "ZiG _selectedAmount"}',
                          style: TextStyle(
                            color: kSubText,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            4,
                            (i) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < pin.length
                                    ? kEcoGreen
                                    : Colors.grey[700],
                                boxShadow: i < pin.length
                                    ? [
                                        BoxShadow(
                                          color: kEcoGreen.withOpacity(0.5),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                          ),
                        ),
                        if (pinError) ...[
                          SizedBox(height: 8),
                          Text(
                            'Incorrect PIN. Try again.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                        SizedBox(height: 20),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.8,
                          physics: const NeverScrollableScrollPhysics(),
                          children: keys.map((k) {
                            if (k.isEmpty) return SizedBox();
                            return GestureDetector(
                              onTap: () => k == '⌫' ? onDelete() : onKey(k),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: k == '⌫'
                                      ? Colors.red.withOpacity(0.1)
                                      : (globalDarkMode.value ? kText : Colors.black).withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: k == '⌫'
                                        ? Colors.red.withOpacity(0.3)
                                        : (globalDarkMode.value ? kText : Colors.black).withOpacity(0.1),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    k,
                                    style: TextStyle(
                                      color: k == '⌫'
                                          ? Colors.red[300]
                                          : kText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showProcessingPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kEcoGreen.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                color: kEcoGreen,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Processing Payment',
              style: TextStyle(
                color: kText,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please wait while EcoCash processes your transaction...',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSubText, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              'Do not close the app.',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _showEconetPopup(String title, String message, {required bool success}) {
    if (success) {
      Vibration.vibrate(duration: 300);
      FlutterRingtonePlayer().playNotification();
    } else {
      Vibration.vibrate(duration: 600);
      FlutterRingtonePlayer().playNotification();
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2332),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: success ? kEcoGreen : Colors.red,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: success ? kEcoGreen : Colors.red,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.signal_cellular_alt,
                      color: kText,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Econet Zimbabwe',
                      style: TextStyle(
                        color: kText,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'SMS',
                      style: TextStyle(color: (globalDarkMode.value ? Colors.white70 : Colors.black87), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (success ? kEcoGreen : Colors.red)
                                .withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            success ? Icons.check_circle : Icons.error,
                            color: success ? kEcoGreen : Colors.red,
                            size: 20,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          title,
                          style: TextStyle(
                            color: kText,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        message,
                        style: TextStyle(
                          color: (globalDarkMode.value ? Colors.white70 : Colors.black87),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: success ? kEcoGreen : Colors.red,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'OK',
                              style: TextStyle(color: kText),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentTab(String id, String label, Color color) {
    bool isSelected = _paymentMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = id),
      child: Container(
        width: (MediaQuery.of(context).size.width - 40 - 16) / 3, // 3 columns
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : kCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(label, style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold, fontSize: 12,
          )),
        ),
      ),
    );
  }

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: kSubText, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: kText,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Up',
              style: TextStyle(
                color: kGreen,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Local Payments · ZESA Token',
              style: TextStyle(color: kSubText, fontSize: 13),
            ),
            SizedBox(height: 24),
            // ── Payment Method Tabs ──────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _paymentTab('ecocash', 'EcoCash', kEcoGreen),
                _paymentTab('onemoney', 'OneMoney', Colors.orange),
                _paymentTab('innbucks', 'InnBucks', Colors.blue),
                _paymentTab('paynow', 'Paynow', Colors.purple),
                _paymentTab('card', 'Card', Colors.indigo),
                _paymentTab('token', 'ZESA Token', kGreen),
              ],
            ),
            SizedBox(height: 24),
            if (['ecocash', 'onemoney', 'innbucks', 'paynow', 'card'].contains(_paymentMethod)) ...[
              // Currency Selector Tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedCurrency = 'USD';
                          _selectedAmount = 5;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedCurrency == 'USD' ? kEcoGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'USD Wallet',
                              style: TextStyle(
                                color: _selectedCurrency == 'USD' ? kText : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedCurrency = 'ZiG';
                          _selectedAmount = 100;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedCurrency == 'ZiG' ? kEcoGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'ZiG Wallet (ZWG)',
                              style: TextStyle(
                                color: _selectedCurrency == 'ZiG' ? kText : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Select Amount ($_selectedCurrency)',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: (_selectedCurrency == 'USD' ? [5, 10, 20, 50] : [100, 200, 500, 1000]).map((amt) {
                  final sel = amt == _selectedAmount;
                  final double rate = _selectedCurrency == 'USD' ? 0.35 : 8.75;
                  final String symbol = _selectedCurrency == 'USD' ? '\$' : 'ZiG ';
                  return GestureDetector(
                    onTap: () => setState(() => _selectedAmount = amt),
                    child: Container(
                      width: 76,
                      height: 72,
                      decoration: BoxDecoration(
                        color: sel ? kEcoGreen : kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel ? kEcoGreen : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$symbol$amt',
                            style: TextStyle(
                              color: kText,
                              fontSize: _selectedCurrency == 'USD' ? 18 : 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${(amt / rate).toStringAsFixed(0)} Units',
                            style: TextStyle(
                              color: sel ? (globalDarkMode.value ? Colors.white70 : Colors.black87) : Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 20),
              Text(
                'Target Meter Number',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _meterController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: kText),
                decoration: InputDecoration(
                  hintText: 'e.g. 1234567890',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(Icons.electric_meter, color: kGreen),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kGreen),
                  ),
                ),
              ),
              SizedBox(height: 20),
              if (_paymentMethod == 'ecocash') ...[
                Text('EcoCash Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '077XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: kGreen), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kGreen)))),
              ] else if (_paymentMethod == 'onemoney') ...[
                Text('OneMoney Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _oneMoneyController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '071XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: Colors.orange), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange)))),
              ] else if (_paymentMethod == 'innbucks') ...[
                Text('InnBucks Registered Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _innbucksController, keyboardType: TextInputType.phone, style: TextStyle(color: kText), decoration: InputDecoration(hintText: '07XXXXXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.phone, color: Colors.blue), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.blue)))),
              ] else if (_paymentMethod == 'card') ...[
                Text('Card Number', style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                SizedBox(height: 8),
                TextField(controller: _cardNumberController, keyboardType: TextInputType.number, style: TextStyle(color: kText), decoration: InputDecoration(hintText: 'XXXX XXXX XXXX XXXX', hintStyle: TextStyle(color: Colors.grey[600]), prefixIcon: Icon(Icons.credit_card, color: Colors.indigo), filled: true, fillColor: kCard, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo)))),
              ] else if (_paymentMethod == 'paynow') ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('Paynow gateway will open in your browser to complete the transaction securely.', style: TextStyle(color: Colors.purple, fontSize: 13))),
              ],
              SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kEcoGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kEcoGreen.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    _confirmRow('You pay', _selectedCurrency == 'USD' ? '\$$_selectedAmount USD' : 'ZiG $_selectedAmount'),
                    _confirmRow(
                      'You receive',
                      '${(_selectedAmount / (_selectedCurrency == 'USD' ? 0.35 : 8.75)).toStringAsFixed(2)} Units',
                    ),
                    _confirmRow('Rate', _selectedCurrency == 'USD' ? '\$0.35 per Units (ZESA)' : 'ZiG 8.75 per Units (ZESA)'),
                  ],
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () {
                    if (_paymentMethod == 'ecocash') _initiatePayment();
                    else if (_paymentMethod == 'onemoney') _initiateOneMoney();
                    else if (_paymentMethod == 'innbucks') _initiateInnBucks();
                    else if (_paymentMethod == 'paynow') _initiatePaynow();
                    else if (_paymentMethod == 'card') _initiateCardPayment();
                  },
                  icon: _loading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kText))
                      : Icon(Icons.payment, color: kText),
                  label: Text(
                    'Pay with ${_paymentMethod.toUpperCase()} ($_selectedCurrency)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kText),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _paymentMethod == 'onemoney' ? Colors.orange : 
                                     _paymentMethod == 'innbucks' ? Colors.blue : 
                                     _paymentMethod == 'paynow' ? Colors.purple : 
                                     _paymentMethod == 'card' ? Colors.indigo : kEcoGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(height: 8),
              Text(
                'Target Meter Number',
                style: TextStyle(color: Colors.grey[300], fontSize: 13),
              ),
              SizedBox(height: 8),
              TextField(
                controller: _meterController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: kText),
                decoration: InputDecoration(
                  hintText: 'e.g. 1234567890',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(Icons.electric_meter, color: kGreen),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kGreen),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Enter ZESA Token',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Enter the 20-digit token from your ZESA receipt',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: kText, letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: '1234-5678-9012-3456-7890',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  prefixIcon: Icon(
                    Icons.confirmation_number,
                    color: kGreen,
                  ),
                  filled: true,
                  fillColor: kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kGreen),
                  ),
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _redeemToken,
                  icon: _loading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.check, color: kText),
                  label: Text(
                    'Redeem Token',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kText,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 6. NOTIFICATIONS PAGE
// ════════════════════════════════════════════════════════════
class NotificationsPage extends StatefulWidget {
  final VoidCallback onUpdate;
  const NotificationsPage({super.key, required this.onUpdate});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    color: kGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => globalNotifications.clear());
                    widget.onUpdate();
                  },
                  child: Text(
                    'Clear all',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (globalNotifications.isEmpty)
              Center(
                child: Column(
                  children: [
                    SizedBox(height: 60),
                    Icon(
                      Icons.notifications_none,
                      color: Colors.grey[600],
                      size: 60,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No notifications yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: globalNotifications.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final n = globalNotifications[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: n.color.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: n.color.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(n.icon, color: n.color, size: 20),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style: TextStyle(
                                    color: kText,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  n.body,
                                  style: TextStyle(
                                    color: kSubText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _timeAgo(n.time),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 7. METER DETAILS PAGE
// ════════════════════════════════════════════════════════════
class MeterDetailsPage extends StatelessWidget {
  const MeterDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final details = [
      ['Meter Serial No.', 'ZW-2024-00142'],
      ['Account Number', '1042-8871-ZW'],
      ['Meter Type', 'Smart Prepaid (IoT)'],
      ['Tariff', 'Domestic (D1)'],
      ['Rate', '\$0.35 / Units'],
      ['Phase', 'Single Phase'],
      ['Supply Voltage', '220V / 50Hz'],
      ['Max Load', '60A'],
      ['Location', 'Harare, Zimbabwe'],
      ['ZESA District', 'Harare Metro'],
      ['Installation Date', '12 Jan 2024'],
      ['Last Sync', 'Just now'],
      ['Firmware', 'v2.1.4'],
      ['Signal Strength', '4G LTE — Excellent'],
    ];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        title: Text(
          'Meter Details',
          style: TextStyle(color: kGreen, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kGreen.withOpacity(0.2),
                    Colors.blueAccent.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGreen.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.electric_meter, color: kGreen, size: 48),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SmartMeter ZW',
                        style: TextStyle(
                          color: kText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ZW-2024-00142',
                        style: TextStyle(color: kGreen, fontSize: 14),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: kGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Active & Connected',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: details.asMap().entries.map((entry) {
                  final i = entry.key;
                  final d = entry.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              d[0],
                              style: TextStyle(
                                color: kSubText,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              d[1],
                              style: TextStyle(
                                color: kText,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < details.length - 1)
                        Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 8. AI CHATBOT PAGE — Keyword based
// ════════════════════════════════════════════════════════════
class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});
  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final List<Map<String, String>> _messages = [
    {
      'role': 'assistant',
      'text': currentMeterNumber.startsWith('GUEST')
          ? 'Hi Guest! 👋 I\'m your SmartMeter payment assistant.\n\nI can help you:\n💳 Buy electricity for any meter\n📲 Understand EcoCash payment steps\n💰 Check rates (USD & ZiG)\n❓ Answer any ZESA questions\n\nWhat do you need help with? ⚡'
          : 'Hi! I\'m your SmartMeter AI assistant. Ask me about your electricity usage, tips to save power, or anything about your ZESA account! ⚡',
    },
  ];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _typing = false;

  final Map<String, String> _responses = {
    // ── Natural language phrases ───────────────────────────
    'how do i buy':
        'To buy electricity:\n1. Tap the Top Up tab\n2. Select amount (\$5, \$10, \$20, \$50)\n3. Enter your EcoCash number\n4. Confirm and enter your PIN\nUnits are added instantly! ⚡',
    'how to buy':
        'To buy electricity, go to Top Up → select amount → pay via EcoCash. Or enter a ZESA token if you have one.',
    'how to top':
        'To top up:\n1. Tap Top Up at the bottom\n2. Choose EcoCash or ZESA Token\n3. Select amount and confirm\nDone in under a minute!',
    'how do i top':
        'To top up, tap the Top Up tab, select your amount, enter your EcoCash number, confirm, and enter your PIN. Units are added immediately.',
    'when will':
        'Your units will run out based on your current consumption rate. Check the Dashboard for your live kW usage and balance. The lower your kW, the longer units last.',
    'how long':
        'How long your units last depends on consumption. At 1 kW average, 10 Units lasts 10 hours. At 0.5 kW average, it lasts 20 hours. Check your Dashboard for live consumption.',
    'finish':
        'Your units will finish faster if you\'re using high-power appliances. Check your live kW on the Dashboard — lower means units last longer. Top up before balance hits 0.',
    'run out':
        'To avoid running out, check your balance regularly on the Dashboard. The app alerts you at 5 Units. Top up via EcoCash before it reaches 0.',
    'last':
        'How long your units last depends on your usage. Check the History tab to see your daily average. Divide your balance by your daily average to estimate days remaining.',
    'how much left':
        'Your current unit balance is shown on the Dashboard in Units. Tap the Dashboard tab to see it live.',
    'buy electric':
        'To buy electricity, go to Top Up → EcoCash → select amount → confirm payment. Or use a ZESA token voucher.',
    'get electric':
        'You can get electricity units via EcoCash payment or a ZESA token. Tap the Top Up tab and follow the steps.',
    'purchase':
        'To purchase electricity units, tap Top Up, choose your amount, and pay via EcoCash. Units are credited instantly.',
    'add electric':
        'To add electricity, go to Top Up and pay via EcoCash or redeem a ZESA token. The minimum is \$5 USD (~14 Units).',
    'pay electric':
        'Pay for electricity via EcoCash in the Top Up tab. Select \$5, \$10, \$20, or \$50, enter your number, confirm, and enter your PIN.',
    'why is':
        'If your power went off, check: 1) Balance on Dashboard (top up if 0), 2) Load shedding schedule for your area, 3) Your main breaker. Call ZESA on 08677 if all OK.',
    'what is':
        'SmartMeter ZW is a smart prepaid electricity meter for Zimbabwe\'s ZESA grid. It monitors your balance, consumption, and voltage in real time via a mobile app.',
    'can i':
        'Yes! You can top up, monitor usage, view history, check voltage, and get alerts all from this app. What specifically would you like to do?',
    'how can':
        'You can manage your electricity entirely through this app — top up, view balance, usage history, alerts, and meter details. What do you need help with?',
    'not working':
        'If something isn\'t working:\n• Dashboard offline → check server and hotspot\n• Top up failed → check EcoCash balance\n• No power → check balance, load shedding, or call ZESA 08677',
    'help':
        'I can help with:\n⚡ Balance & top-up\n📊 Usage history\n💡 Saving tips\n💰 Tariffs & costs\n🔒 Tamper alerts\n📞 ZESA contacts\n⚡ Load shedding\nWhat do you need?',
    'what can':
        'I can answer questions about your electricity balance, how to top up, usage history, tariffs, power saving tips, tamper alerts, voltage, load shedding, and ZESA contacts.',
    'hello': 'Hello! Welcome to SmartMeter ZW. How can I help you today? ⚡',
    'hi':
        'Hi there! I\'m your SmartMeter assistant. Ask me anything about your electricity.',
    'hey': 'Hey! What would you like to know about your meter or electricity?',
    'good morning':
        'Good morning! How can I help you with your electricity today?',
    'good afternoon': 'Good afternoon! What can I help you with?',
    'good evening': 'Good evening! Need help with your meter or electricity?',
    'how are you':
        'I\'m running perfectly, just like your meter! How can I help you?',
    'thank':
        'You\'re welcome! Feel free to ask anything else about your meter.',
    'thanks': 'Happy to help! Let me know if you need anything else.',
    'bye': 'Goodbye! Stay powered up! ⚡',

    // ── Balance ────────────────────────────────────────────
    'balance':
        'Your current unit balance is shown live on the Dashboard. If it\'s below 5 Units the app will alert you automatically. Top up via EcoCash or ZESA token anytime.',
    'units':
        'Your remaining units are shown on the Dashboard. Units drain based on how much power you use — heavier appliances drain faster.',
    'kwh':
        'A Unit is the standard measure ZESA uses for prepay electricity. 1 Unit = 1 kWh (kilowatt-hour). At \$0.35 USD (or 8.75 ZiG) per Unit, 10 Units cost \$3.50 USD (or 87.50 ZiG).',
    'low':
        'When your balance drops below 5 Units, the app sends an automatic alert. Top up immediately to avoid a power cut. Go to Top Up → EcoCash.',
    'empty':
        'If your balance reaches 0 Units, your power supply will be disconnected automatically. Top up immediately to restore power.',
    'running out':
        'To avoid running out of power, top up before your balance drops to 0. The app alerts you at 5 Units remaining.',
    'credit':
        'Your unit credit is shown on the Dashboard as "Unit Balance". This is the amount of electricity you have prepaid for.',

    // ── Top Up ─────────────────────────────────────────────
    'top up':
        'You can top up in two ways:\n• EcoCash — tap Top Up, enter your number and amount (USD or ZiG)\n• ZESA Token — enter your 20-digit voucher code\nMinimum top-up is \$5 USD or 100 ZiG.',
    'topup':
        'Top up via EcoCash or ZESA token. Go to the Top Up tab at the bottom of the screen. You can choose to pay with USD or ZiG! Rates are \$0.35 USD or 8.75 ZiG per Unit.',
    'recharge':
        'To recharge your meter, go to Top Up tab → select EcoCash or ZESA Token → follow the steps. Your balance updates instantly after payment.',
    'buy units':
        'To buy more units, go to Top Up → select USD or ZiG wallet → select an amount → pay via EcoCash. Units are added immediately.',
    'add units':
        'Go to the Top Up tab, select your currency (USD/ZiG), select your amount, enter your EcoCash number and confirm. Units are added within seconds.',
    'ecocash':
        'To pay via EcoCash:\n1. Tap Top Up\n2. Select USD or ZiG wallet\n3. Select amount\n4. Enter your Econet number\n5. Confirm payment and enter your EcoCash PIN\nUnits are added immediately.',
    'token':
        'To use a ZESA token:\n1. Tap Top Up\n2. Switch to ZESA Token tab\n3. Enter your 20-digit token code\n4. Tap Redeem\nUnits are added instantly.',
    'voucher':
        'Enter your ZESA voucher code in the Top Up screen under the ZESA Token tab. Enter all 20 digits and tap Redeem.',
    'minimum':
        'The minimum top-up amount is \$5 USD (approx. 14 Units) or 100 ZiG (approx. 11.4 Units).',
    'how much':
        'Standard rates (\$0.35 USD or 8.75 ZiG per Unit):\n• \$5 USD = ~14 Units | 100 ZiG = ~11.4 Units\n• \$10 USD = ~28 Units | 200 ZiG = ~22.8 Units\n• \$20 USD = ~57 Units | 500 ZiG = ~57.1 Units\n• \$50 USD = ~142 Units | 1000 ZiG = ~114.3 Units',
    'payment':
        'Payments are processed via EcoCash. After confirming and entering your PIN, units are added to your meter within seconds.',
    'receipt':
        'After a successful EcoCash payment, you receive an on-screen receipt with your token number, units added, and new balance.',
    'failed':
        'If your payment failed, check:\n• Your EcoCash wallet has sufficient balance\n• Your Econet number is correct\n• Your internet connection is active\nThen try again.',
    'pin':
        'Your EcoCash PIN is the 4-digit PIN you set when you registered for EcoCash. It\'s not the same as your SmartMeter app PIN.',
    'zig':
        'Yes, you can now purchase electricity units using ZiG (Zimbabwe Gold)! Just go to the Top Up tab, select EcoCash, choose "ZiG Wallet (ZWG)", pick an amount (ZiG 100, 200, 500, or 1000) and complete the payment. Units are credited instantly at 8.75 ZiG per Unit!',
    'zwg':
        'ZiG (Zimbabwe Gold) is fully supported! You can top up using your EcoCash ZiG wallet at a standard tariff rate of 8.75 ZiG per Unit (equivalent to \$0.35 USD).',

    // ── Tariff & Cost ──────────────────────────────────────
    'tariff':
        'You\'re on the Domestic D1 tariff — \$0.35 USD (or 8.75 ZiG) per Unit. This is ZESA\'s standard residential rate for households using up to 200 Units per month.',
    'rate':
        'The current ZESA electricity rate is \$0.35 USD (or 8.75 ZiG) per Unit on the Domestic D1 tariff. This is fixed by ZESA and applies to standard residential customers.',
    'price':
        'Electricity costs \$0.35 USD (or 8.75 ZiG) per Unit. So if you use 10 Units per day, that\'s \$3.50 USD (or 87.50 ZiG) per day.',
    'cost':
        'Your electricity cost is \$0.35 USD (or 8.75 ZiG) per Unit. Check your Usage History to see how many Units you use per day and estimate your monthly cost.',
    'expensive':
        'To reduce your electricity costs:\n1. Use LED bulbs instead of incandescent\n2. Switch off the geyser during peak hours\n3. Unplug devices on standby\n4. Use appliances at off-peak times (10PM–6AM)',
    'cheap':
        'The cheapest time to run heavy appliances is off-peak hours — between 10PM and 6AM. This doesn\'t change your rate but helps ZESA\'s grid load.',
    'zesa rate':
        'ZESA charges \$0.35 USD (or 8.75 ZiG) per Unit on the Domestic D1 tariff. Rates can change — check the ZESA website or app notifications for updates.',

    // ── Consumption & Usage ────────────────────────────────
    'consumption':
        'Your live power consumption in kW is shown on the Dashboard. A higher kW means more units are being used right now.',
    'usage':
        'Check the History tab for your last 7 days of usage. Your daily average, total, and peak usage are shown at the bottom.',
    'history':
        'The History tab shows your electricity usage for the last 7 days in Units per day, with your total, average, and peak usage.',
    'how much do i use':
        'Check the History tab — it shows your daily usage for the past 7 days. Your average daily usage is shown at the bottom.',
    'daily':
        'Your daily electricity usage is shown in the History tab. The average Zimbabwean household uses 10–15 Units per day.',
    'monthly':
        'To estimate your monthly usage, multiply your daily average (from History tab) by 30. At \$0.35 per Unit, 300 Units per month = \$105 USD (or 2625 ZiG).',
    'watt':
        'Watts measure power usage at a moment in time. 1000 watts = 1 kW = 1 Units used per hour. Your live wattage is shown as kW on the Dashboard.',
    'appliance':
        'Typical appliance usage:\n• Geyser: 3–4 kW\n• Electric stove: 2–3 kW\n• Fridge: 0.1–0.3 kW\n• TV: 0.1–0.2 kW\n• LED bulb: 0.01 kW\n• Iron: 1–2 kW',
    'geyser':
        'Your geyser is one of the biggest electricity consumers — it uses 3–4 kW. Switch it off during peak hours (6–9AM and 5–9PM) to save units.',
    'fridge':
        'A fridge uses about 0.1–0.3 kW continuously. It\'s always on, so make sure it\'s energy-efficient and the door seals are tight.',
    'stove':
        'An electric stove uses 2–3 kW. Use it efficiently — put lids on pots, match pot size to plate size, and turn off before food is fully cooked.',
    'television':
        'A TV uses about 0.1–0.2 kW. Switch it off (not standby) when not in use. Standby mode still consumes electricity.',
    'air condition':
        'Air conditioners use 1–3 kW depending on size. Set the temperature to 24–26°C for efficiency and clean filters regularly.',
    'lights':
        'Switch to LED bulbs — they use 80% less electricity than incandescent bulbs. A LED bulb uses only 0.01 kW vs 0.06 kW for incandescent.',

    // ── Saving Tips ────────────────────────────────────────
    'save':
        'Top electricity saving tips:\n1. Switch off geyser during peak hours\n2. Use LED bulbs\n3. Unplug devices on standby\n4. Use appliances at night (off-peak)\n5. Fix dripping hot taps\n6. Use a microwave instead of stove',
    'saving':
        'To save electricity:\n• Turn off lights in empty rooms\n• Use cold water wash for laundry\n• Keep fridge away from heat sources\n• Insulate your geyser\n• Use natural light during the day',
    'reduce':
        'To reduce your ZESA bill, focus on your geyser (biggest consumer), switch to LED lighting, and unplug devices when not in use. Check your History tab to see your peak usage days.',
    'tips':
        'Smart electricity tips for Zimbabwe:\n1. Solar geyser saves ~40% on bills\n2. Prepay meters help you monitor usage\n3. Run washing machine at full load only\n4. Air-dry clothes instead of using a dryer\n5. Use a pressure cooker to save cooking energy',
    'peak':
        'Peak electricity hours in Zimbabwe are 6–9AM and 5–9PM. Avoid running heavy appliances (geyser, stove, iron) during these times to preserve your units.',
    'off peak':
        'Off-peak hours are 10PM–6AM. This is the best time to run heavy appliances like washing machines, dishwashers, and to charge your electric geyser timer.',

    // ── Voltage & Power Quality ────────────────────────────
    'voltage':
        'Your current supply voltage is shown on the Dashboard. Normal ZESA supply is 220–240V at 50Hz. If voltage drops below 200V consistently, contact ZESA.',
    'power cut':
        'If you have a power cut:\n1. Check your unit balance — if 0 Units, top up\n2. Check if neighbours have power (load shedding)\n3. Check your main circuit breaker\n4. If none apply, call ZESA on 08677',
    'load shed':
        'Load shedding is ZESA\'s scheduled power cuts to manage grid demand. Check the ZESA website or WhatsApp groups for your area\'s schedule. Group 5, Harare Metro.',
    'loadshedding':
        'Load shedding schedules for Harare are published by ZESA. Your area is Group 5 — check zesa.co.zw for the latest schedule.',
    'outage':
        'If you have a power outage, first check your unit balance on the Dashboard. If balance is OK, check if it\'s load shedding. If not, call ZESA on 08677.',
    'no power':
        'If you have no power:\n1. Check balance on Dashboard (top up if 0)\n2. Check load shedding schedule for your area\n3. Check your DB board breakers\n4. Call ZESA on 08677 if all OK',
    'flicker':
        'Voltage fluctuations cause flickering lights. This can damage appliances. If it\'s frequent, report to ZESA on 08677. Consider a voltage stabiliser for sensitive equipment.',
    'surge':
        'Power surges can damage appliances. Use surge protectors for computers and TVs. If surges are frequent, report to ZESA on 08677.',
    'frequency':
        'Zimbabwe\'s electricity supply is 50Hz single phase. Your meter monitors this. Normal frequency is 49.5–50.5Hz.',

    // ── Meter & Hardware ───────────────────────────────────
    'meter':
        'Your SmartMeter ZW (Serial: ZW-2024-00142) is an IoT-connected prepaid meter. It monitors balance, consumption, voltage, and tamper status in real time.',
    'serial':
        'Your meter serial number is ZW-2024-00142. You can find full meter details in the Meter Details screen — tap the ONLINE badge on the Dashboard.',
    'model':
        'Your meter is a SmartMeter ZW IoT Prepaid Meter, connected via 4G LTE to the cloud. It replaces the traditional ZESA keypad meter.',
    'firmware':
        'Your meter firmware is v2.1.4. Firmware updates are applied automatically over the air when connected. Check Meter Details for the latest version.',
    'signal':
        'Your meter is connected via 4G LTE with Excellent signal strength. This ensures real-time data updates every 5 seconds.',
    'connection':
        'Your meter connects to the SmartMeter ZW server via 4G LTE mobile data. This is separate from your home WiFi — no router needed.',
    'offline':
        'If the app shows OFFLINE, check:\n1. Is the Flask server running on the laptop?\n2. Is your phone on the PC hotspot?\n3. Is the hotspot firewall disabled?\nRestart the server if needed.',
    'online':
        'When the Dashboard shows ONLINE (green dot), your meter is connected and data is updating every 5 seconds.',
    'sync':
        'Your meter syncs data every 5 seconds. The last sync time is shown in Meter Details. If sync is delayed, check your connection.',
    'account':
        'Your account number is 1042-8871-ZW. This is your ZESA account identifier. Keep it safe — you may need it for billing queries.',
    'account number':
        'Your ZESA account number is 1042-8871-ZW. Use this when contacting ZESA for billing or technical issues.',

    // ── Tamper & Security ──────────────────────────────────
    'tamper':
        'A tamper alert means unauthorized physical access to your meter was detected. This is a serious security event. Contact ZESA immediately on 08677 and report the incident.',
    'tampering':
        'Meter tampering is illegal in Zimbabwe and can result in prosecution. If you receive a tamper alert, contact ZESA on 08677. Do not attempt to fix it yourself.',
    'theft':
        'Electricity theft is a criminal offence. If you suspect someone is stealing electricity from your meter, contact ZESA on 08677 or the police.',
    'bypass':
        'Bypassing a prepaid meter is illegal and dangerous. It can cause fires and electrocution. SmartMeter ZW detects bypasses and alerts ZESA automatically.',
    'hack':
        'SmartMeter ZW has built-in tamper detection and sends alerts to both the app and ZESA in real time. The meter is sealed and any tampering is logged.',
    'security':
        'Your meter is protected by tamper sensors, encrypted communication, and real-time monitoring. Any unauthorized access triggers an immediate alert to both you and ZESA.',
    'alert':
        'Alerts appear in the Notifications tab (bell icon). You\'ll be notified for tamper detection, low balance, and successful top-ups.',
    'notification':
        'Check the Notifications tab for all alerts. You\'ll receive alerts for:\n• Tamper detection\n• Low balance (below 5 Units)\n• Successful top-ups\n• System events',

    // ── App & Settings ─────────────────────────────────────
    'app':
        'SmartMeter ZW app lets you monitor your electricity balance, consumption, voltage, usage history, and top up — all from your phone.',
    'dashboard':
        'The Dashboard shows your live unit balance, consumption in kW, voltage, meter status, and quick access to AI Assistant and Meter Details.',
    'settings':
        'In Settings you can manage notification preferences (low balance alerts, tamper alerts, daily summary), appearance, and account info.',
    'login':
        'The app uses a 4-digit PIN for security. The demo PIN is 1234. Change it in Settings after deployment for real security.',
    'logout':
        'To logout, go to Settings → scroll to the bottom → tap Logout. You\'ll be returned to the PIN screen.',
    'notification setting':
        'Go to Settings → Notifications to toggle Low Balance Alert, Tamper Alert, and Daily Summary on or off.',
    'dark mode':
        'Dark mode is enabled by default and can be toggled in Settings → Appearance.',
    'version':
        'SmartMeter ZW app version 1.0.0. This is the first release developed for the UZ Research Innovation Week 2026.',

    // ── ZESA Contact & Support ─────────────────────────────
    'contact':
        'ZESA contact details:\n• Emergency: 08677\n• Website: zesa.co.zw\n• Address: 25 Samora Machel Ave, Harare\n• Meter faults: 08677 or nearest ZESA office',
    'zesa':
        'ZESA (Zimbabwe Electricity Supply Authority) is Zimbabwe\'s national electricity supplier. Contact them on 08677 or visit zesa.co.zw for support.',
    'emergency':
        'For electricity emergencies call ZESA on 08677. For meter tampering, also contact the police on 995.',
    'report':
        'To report a fault, contact ZESA on 08677 or visit your nearest ZESA office. For tamper alerts, the app notifies ZESA automatically.',
    'fault':
        'For meter faults, call ZESA on 08677. The SmartMeter ZW system logs all events which can help ZESA diagnose issues faster.',
    'support':
        'For app support, contact the SmartMeter ZW team at UZ. For ZESA billing or meter issues, call 08677 or visit zesa.co.zw.',
    'complain':
        'For ZESA complaints, contact them on 08677 or email info@zesa.co.zw. For SmartMeter ZW app issues, contact the UZ development team.',

    // ── Billing & Payments ─────────────────────────────────
    'bill':
        'SmartMeter ZW is a prepaid system — you pay before you use. There are no monthly bills. Top up when needed and track spending via the History tab.',
    'prepaid':
        'Your SmartMeter ZW is a prepaid meter. You buy units in advance via EcoCash or ZESA token. When units run out, supply disconnects automatically.',
    'postpaid':
        'SmartMeter ZW is prepaid only. There is no postpaid (monthly bill) option on this meter. You must top up before your balance reaches 0.',
    'debt':
        'With a prepaid meter, there\'s no debt — you only use what you\'ve paid for. When balance hits 0, power disconnects until you top up.',
    'change':
        'To change your top-up amount, simply select a different amount (\$5, \$10, \$20, \$50) on the Top Up screen before confirming payment.',

    // ── Environment & Solar ────────────────────────────────
    'solar':
        'SmartMeter ZW can monitor solar hybrid systems. If you have solar panels, the meter can track export and import. Contact ZESA to configure net metering.',
    'renewable':
        'Zimbabwe has strong solar potential. A 5kW solar system can offset most household consumption. SmartMeter ZW supports hybrid grid/solar monitoring.',
    'environment':
        'Using less electricity reduces Zimbabwe\'s reliance on coal and hydro imports. Every Units saved helps the national grid and reduces your bill.',
    'carbon':
        'Zimbabwe\'s electricity mix includes coal (Hwange) and hydro (Kariba). Reducing consumption lowers your carbon footprint and eases grid demand.',

    // ── Project Info ───────────────────────────────────────
    'who made':
        'SmartMeter ZW was developed by a team at the University of Zimbabwe for the 2026 Research Innovation & Industrialisation Week.',
    'developer':
        'SmartMeter ZW was developed at the University of Zimbabwe. The system includes IoT hardware, a mobile app, and a cloud backend.',
    'university':
        'SmartMeter ZW is a University of Zimbabwe research project presented at the 2026 UZ Research Innovation & Industrialisation Week.',
    'research':
        'SmartMeter ZW is a research project exploring next-generation prepaid metering for Zimbabwe\'s ZESA grid using IoT, AI, and mobile technology.',
    'project':
        'SmartMeter ZW is an IoT smart electricity metering system designed for Zimbabwe. It features real-time monitoring, mobile control, AI assistance, and EcoCash payments.',
    'innovation':
        'SmartMeter ZW innovates on traditional ZESA keypad meters by adding WiFi/4G connectivity, a mobile app, AI assistant, tamper detection, and EcoCash integration.',
  };

  String _getResponse(String input) {
    final lower = input.toLowerCase();
    // Check for multi-word keywords first (longer matches take priority)
    final sorted = _responses.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sorted) {
      if (lower.contains(key)) return _responses[key]!;
    }
    return 'I can help with your balance, top-up, usage history, tariffs, saving tips, tamper alerts, voltage, load shedding, ZESA contacts, and more. What would you like to know?';
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _typing = true;
    });
    _scrollToBottom();
    await Future.delayed(const Duration(milliseconds: 1200));
    final response = _getResponse(text);
    setState(() {
      _messages.add({'role': 'assistant', 'text': response});
      _typing = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients)
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kGreen.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy, color: kGreen, size: 20),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    color: kText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: kGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Online',
                      style: TextStyle(color: kGreen, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children:
                  [
                    'My balance',
                    'Usage tips',
                    'Top up help',
                    'Tariff info',
                    'Tamper alert',
                  ].map((q) {
                    return GestureDetector(
                      onTap: () {
                        _ctrl.text = q;
                        _send();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kGreen.withOpacity(0.3)),
                        ),
                        child: Text(
                          q,
                          style: TextStyle(color: kGreen, fontSize: 12),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length && _typing)
                  return _buildTypingIndicator();
                final m = _messages[i];
                final isUser = m['role'] == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? kGreen : kCard,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: Text(
                      m['text']!,
                      style: TextStyle(
                        color: isUser ? Colors.black : (globalDarkMode.value ? Colors.white70 : Colors.black87),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: kCard,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: TextStyle(color: kText),
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Ask about your electricity...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: kBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (i) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 400 + (i * 150)),
              builder: (_, v, __) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.4 + (v * 0.6)),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 9. SETTINGS PAGE
// ════════════════════════════════════════════════════════════
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _lowBalanceAlert = true;
  bool _tamperAlert = true;
  bool _dailySummary = false;
  bool _darkMode = true;

  Future<void> _consumeUnits(int amount) async {
    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/consume/$amount'),
        headers: {'X-Meter-Number': currentMeterNumber},
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Consumed $amount Units')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error consuming units: $e');
    }
  }

  Future<void> _resetUnits() async {
    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/reset_units'),
        headers: {'X-Meter-Number': currentMeterNumber},
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Units Reset to 50')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error resetting units: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(
                color: kGreen,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: kGreen.withOpacity(0.2),
                    child: Icon(Icons.person, color: kGreen, size: 28),
                  ),
                  SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUsername,
                        style: TextStyle(
                          color: kText,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Meter: $currentMeterNumber',
                        style: TextStyle(color: kSubText, fontSize: 12),
                      ),
                      Text(
                        'Harare, Zimbabwe',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            _sectionTitle('Notifications'),
            _switchTile(
              'Low Balance Alert',
              'Alert when balance < 5 Units',
              Icons.battery_alert,
              Colors.orange,
              _lowBalanceAlert,
              (v) => setState(() => _lowBalanceAlert = v),
            ),
            _switchTile(
              'Tamper Alert',
              'Alert on unauthorized access',
              Icons.warning,
              Colors.red,
              _tamperAlert,
              (v) => setState(() => _tamperAlert = v),
            ),
            _switchTile(
              'Daily Summary',
              'Daily usage report at 8PM',
              Icons.summarize,
              Colors.blueAccent,
              _dailySummary,
              (v) => setState(() => _dailySummary = v),
            ),
            SizedBox(height: 8),
            _sectionTitle('Appearance'),
            _switchTile(
              'Dark Mode',
              'Use dark theme',
              Icons.dark_mode,
              kGreen,
              globalDarkMode.value,
              (v) {
                setState(() => _darkMode = v);
                globalDarkMode.value = v;
              },
            ),
            SizedBox(height: 8),
            _sectionTitle('About'),
            _infoTile('App Version', 'SmartMeter ZW v1.0.0'),
            _infoTile('Server', BASE_URL),
            _infoTile('Developer', 'UZ Research Innovation 2026'),
            SizedBox(height: 20),
            _sectionTitle('Debug Actions'),
            _debugActionTile('Consume 10 Units', Icons.battery_charging_full, Colors.orange, () => _consumeUnits(10)),
            _debugActionTile('Reset Units', Icons.refresh, Colors.blue, _resetUnits),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                ),
                icon: Icon(Icons.logout, color: Colors.red),
                label: Text(
                  'Logout',
                  style: TextStyle(color: Colors.red, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        color: kSubText,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _switchTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: color,
        title: Text(
          title,
          style: TextStyle(color: kText, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[500], fontSize: 11),
        ),
        secondary: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: kSubText, fontSize: 13)),
          Text(
            value,
            style: TextStyle(color: (globalDarkMode.value ? Colors.white70 : Colors.black87), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _debugActionTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: kText, fontSize: 14)),
        trailing: Icon(Icons.arrow_forward_ios, color: kSubText, size: 14),
      ),
    );
  }
}
