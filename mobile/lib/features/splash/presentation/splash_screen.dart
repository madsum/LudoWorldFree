import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/controllers/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    // Fade-in animation (800ms)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();

    // Keep the splash visible briefly, then route based on the restored session.
    _navigationTimer = Timer(const Duration(seconds: 2), _routeFromSession);
  }

  void _routeFromSession() {
    if (!mounted) return;
    final authState = ref.read(authControllerProvider);
    if (authState.isLoading) {
      _navigationTimer = Timer(const Duration(milliseconds: 200), _routeFromSession);
      return;
    }
    context.go(authState.user == null ? '/login' : '/home');
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full-screen Splash Image maintaining aspect ratio without stretching
            Image.asset(
              AppAssets.splashImage,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: AppColors.bgNavy,
                  child: Center(
                    child: Text(
                      AppConstants.appName,
                      style: GoogleFonts.cinzel(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Gradient Overlay at bottom for readable version text without covering iProSoft logo
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 30, bottom: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Version ${AppConstants.appVersion}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
