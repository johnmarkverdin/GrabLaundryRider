import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 ADD
import '../supabase_config.dart';
import '../pages/rider_home_page.dart';

class RiderAuthPage extends StatefulWidget {
  const RiderAuthPage({super.key});

  @override
  State<RiderAuthPage> createState() => _RiderAuthPageState();
}

class _RiderAuthPageState extends State<RiderAuthPage> {
  final _nameCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _confirmCtl = TextEditingController();

  bool _loading = false;
  bool _isSignUp = false;
  bool _showPassword = false;

  // 👇 ADD: remember me flag
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedRider(); // 👈 ADD
  }

  // 👇 ADD: load saved preference + email, optionally auto-continue
  Future<void> _loadRememberedRider() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('rider_remember_me') ?? false;
    final email = prefs.getString('rider_email');

    if (!mounted) return;

    setState(() {
      _rememberMe = remember;
      if (remember && email != null) {
        _emailCtl.text = email;
      }
    });

    if (remember) {
      final session = supabase.auth.currentSession;
      if (session != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const RiderHomePage(),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _emailCtl.dispose();
    _passwordCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _auth() async {
    final name = _nameCtl.text.trim();
    final phone = _phoneCtl.text.trim();
    final email = _emailCtl.text.trim();
    final pass = _passwordCtl.text.trim();
    final confirm = _confirmCtl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      _snack('Email & password are required');
      return;
    }

    if (_isSignUp) {
      if (name.isEmpty || phone.isEmpty || confirm.isEmpty) {
        _snack('Please fill in all fields');
        return;
      }
      if (pass != confirm) {
        _snack('Passwords do not match');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      if (_isSignUp) {
        // RIDER SIGN UP
        final res = await supabase.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': name,
            'phone': phone,
            'role': 'rider',
          },
        );

        if (res.user != null) {
          _snack(
            'Rider account created! Please check your email to confirm, then sign in.',
          );
          setState(() => _isSignUp = false);
        }
      } else {
        // RIDER SIGN IN
        final res = await supabase.auth.signInWithPassword(
          email: email,
          password: pass,
        );

        if (res.session != null) {
          // 👇 ADD: save or clear remember-me preference
          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setBool('rider_remember_me', true);
            await prefs.setString('rider_email', email);
          } else {
            await prefs.remove('rider_remember_me');
            await prefs.remove('rider_email');
          }

          _snack('Welcome back, rider!');

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const RiderHomePage(),
            ),
          );
        } else {
          _snack('Login failed. Please confirm your email or try again.');
        }
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Color(0xFF6366F1),
          width: 1.2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? 'Create Rider Account' : 'Rider Login';
    final subtitle = _isSignUp
        ? 'Join the Laundry Rider network and start delivering clean clothes with ease.'
        : 'Sign in to your rider account and manage today’s pickups and deliveries.';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF4F46E5),
              Color(0xFF6366F1),
              Color(0xFF06B6D4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo / Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.directions_bike_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Laundry Rider Portal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Fast. Reliable. Organized routes for every load.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Toggle Sign In / Sign Up
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_isSignUp) {
                                setState(() => _isSignUp = false);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(50),
                                color: !_isSignUp
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: !_isSignUp
                                      ? const Color(0xFF4F46E5)
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_isSignUp) {
                                setState(() => _isSignUp = true);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(50),
                                color: _isSignUp
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _isSignUp
                                      ? const Color(0xFF4F46E5)
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card with form
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 18),

                        if (_isSignUp) ...[
                          TextField(
                            controller: _nameCtl,
                            decoration: _inputDecoration(
                              'Full Name',
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _phoneCtl,
                            decoration: _inputDecoration(
                              'Phone Number',
                              icon: Icons.phone_rounded,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _emailCtl,
                          decoration: _inputDecoration(
                            'Email Address',
                            icon: Icons.email_outlined,
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordCtl,
                          obscureText: !_showPassword,
                          decoration: _inputDecoration(
                            'Password',
                            icon: Icons.lock_outline_rounded,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                              ),
                            ),
                          ),
                        ),

                        // 👇 ADD: Remember me only for Sign In
                        if (!_isSignUp) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (val) {
                                  setState(() {
                                    _rememberMe = val ?? false;
                                  });
                                },
                                activeColor: const Color(0xFF4F46E5),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Remember me',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (_isSignUp) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _confirmCtl,
                            obscureText: true,
                            decoration: _inputDecoration(
                              'Confirm Password',
                              icon: Icons.lock_person_outlined,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        if (_isSignUp)
                          Row(
                            children: const [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Color(0xFF6B7280),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Use a valid email address — you’ll need to confirm it before you can start accepting deliveries.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_isSignUp) const SizedBox(height: 16),

                        _loading
                            ? const Center(child: CircularProgressIndicator())
                            : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _auth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              _isSignUp
                                  ? 'Create Rider Account'
                                  : 'Sign In',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _isSignUp = !_isSignUp),
                            child: Text(
                              _isSignUp
                                  ? 'Already a rider? Sign in instead'
                                  : 'New here? Create a rider account',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'By continuing, you agree to follow company delivery guidelines,\nprotect customer data, and handle all orders with care.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
