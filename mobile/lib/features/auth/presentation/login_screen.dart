import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/oauth_button.dart';
import '../domain/user_model.dart';
import 'controllers/auth_controller.dart';
import 'widgets/floating_ludo_pieces.dart';
import 'widgets/guest_setup_dialog.dart';
import 'widgets/legal_dialog.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  void _handleOAuthLogin(BuildContext context, WidgetRef ref, AuthProvider provider) async {
    final success = await ref
        .read(authControllerProvider.notifier)
        .signInWithOAuth(provider);
    if (success && context.mounted) {
      context.go('/home');
    } else if (context.mounted) {
      final errorMsg = ref.read(authControllerProvider).errorMessage ?? 'Login failed. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bgNavy,
          content: Text(errorMsg, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  void _handleGuestLogin(BuildContext context) {
    GuestSetupDialog.show(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width >= 650;

    return Scaffold(
      body: FloatingLudoPieces(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? size.width * 0.2 : 20.0,
                vertical: 16.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 10),
                  
                  // Top Logo & Game Header
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.royalBlue.withValues(alpha: 0.2),
                          border: Border.all(color: AppColors.gold, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.3),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.casino_rounded,
                          size: 52,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.gold, Color(0xFFFFF1B8), AppColors.goldDark],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: Text(
                          AppConstants.appName.toUpperCase(),
                          style: GoogleFonts.cinzel(
                            fontSize: isTablet ? 32 : 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppConstants.appSubtitle,
                        style: GoogleFonts.poppins(
                          fontSize: isTablet ? 15 : 13,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Glassmorphism OAuth & Guest Container
                  GlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                    child: Column(
                      children: [
                        Text(
                          'SIGN IN TO PLAY',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // OAuth Provider Buttons
                        OAuthButton(
                          providerName: 'Google',
                          iconData: FontAwesomeIcons.google,
                          backgroundColor: AppColors.googleBg,
                          textColor: AppColors.googleText,
                          iconColor: const Color(0xFF4285F4),
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.google,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.google),
                        ),
                        OAuthButton(
                          providerName: 'Facebook',
                          iconData: FontAwesomeIcons.facebookF,
                          backgroundColor: AppColors.facebookBg,
                          textColor: AppColors.facebookText,
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.facebook,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.facebook),
                        ),
                        OAuthButton(
                          providerName: 'Apple',
                          iconData: FontAwesomeIcons.apple,
                          backgroundColor: AppColors.appleBg,
                          textColor: AppColors.appleText,
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.apple,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.apple),
                        ),
                        OAuthButton(
                          providerName: 'LinkedIn',
                          iconData: FontAwesomeIcons.linkedinIn,
                          backgroundColor: AppColors.linkedinBg,
                          textColor: AppColors.linkedinText,
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.linkedin,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.linkedin),
                        ),
                        OAuthButton(
                          providerName: 'X (Twitter)',
                          iconData: FontAwesomeIcons.xTwitter,
                          backgroundColor: AppColors.twitterBg,
                          textColor: AppColors.twitterText,
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.twitter,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.twitter),
                        ),
                        OAuthButton(
                          providerName: 'GitHub',
                          iconData: FontAwesomeIcons.github,
                          backgroundColor: AppColors.githubBg,
                          textColor: AppColors.githubText,
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.github,
                          onPressed: () => _handleOAuthLogin(context, ref, AuthProvider.github),
                        ),

                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white24)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: Colors.white24)),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Guest Mode Button
                        CustomGameButton(
                          text: 'Continue as Guest',
                          icon: Icons.person_outline_rounded,
                          gradientColors: const [
                            AppColors.guestBtnBg,
                            Color(0xFF2E7D32),
                          ],
                          isLoading: authState.isLoading && authState.loadingProvider == AuthProvider.guest,
                          onPressed: () => _handleGuestLogin(context),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Guests can play vs Computer & Pass & Play. Online multiplayer requires sign-in.',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Legal Section
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'By continuing you agree to our ',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => LegalDialog.show(
                          context,
                          title: 'Terms of Service',
                          content: _sampleTermsOfService,
                        ),
                        child: Text(
                          'Terms of Service',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.gold,
                          ),
                        ),
                      ),
                      Text(
                        ' & ',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => LegalDialog.show(
                          context,
                          title: 'Privacy Policy',
                          content: _samplePrivacyPolicy,
                        ),
                        child: Text(
                          'Privacy Policy',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'by ${AppConstants.publisher}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white38,
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

  static const String _sampleTermsOfService = '''
Welcome to Ludo World Free by iProSoft!

1. Acceptance of Terms
By accessing or playing Ludo World Free, you agree to be bound by these Terms of Service. All gameplay modes are free to play.

2. Account & Fair Play
Users must maintain respectful behavior during online multiplayer matches and avoid any unfair advantage software or exploits.

3. In-Game Items & Virtual Currency
Coins and Diamonds are virtual in-game items with no real-world financial value. They cannot be transferred or exchanged for real currency.

4. Free Service & Advertisements
Ludo World Free is supported by advertisements to keep all gameplay features completely free for players globally.

5. Modifications
iProSoft reserves the right to update or modify these terms at any time. Continued use of the game constitutes acceptance.
''';

  static const String _samplePrivacyPolicy = '''
Ludo World Free Privacy Policy

1. Information We Collect
We collect minimal profile information (such as guest ID or social login display name) necessary to deliver multiplayer leaderboards and player profiles.

2. Data Usage
Your information is strictly used for game authentication, saving game progress, and facilitating online match connectivity.

3. Third-Party Authentication
When you sign in via OAuth providers (Google, Facebook, Apple, LinkedIn, X, GitHub), we receive authentication tokens to securely verify your identity without receiving your raw password.

4. Advertising & Data Safety
We do not sell personal data. Ads served within Ludo World Free follow standard privacy compliance rules.

5. Data Security & Deletion
You can request account data deletion at any time by contacting support@iprosoft.com.
''';
}
