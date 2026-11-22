import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/ads/ad_mob_consent_service.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file for OAuth secrets
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // If .env file is missing in production/test, dotenv will fallback gracefully
  }

  // Set system UI style for immersive dark theme game feel
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: LudoWorldFreeApp(),
    ),
  );
}

class LudoWorldFreeApp extends ConsumerStatefulWidget {
  const LudoWorldFreeApp({super.key});

  @override
  ConsumerState<LudoWorldFreeApp> createState() => _LudoWorldFreeAppState();
}

class _LudoWorldFreeAppState extends ConsumerState<LudoWorldFreeApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final Map<String, DateTime> _recentFriendLinks = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleAppLink);
    unawaited(_openInitialLink());
  }

  Future<void> _openInitialLink() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) _handleAppLink(initialLink);
    } catch (_) {
      // Normal app startup has no initial deep link.
    }
  }

  void _handleAppLink(Uri uri) {
    if (uri.scheme != 'ludoworldfree' || uri.host != 'friend-room') return;
    final code = uri.queryParameters['code'] ??
        (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null);
    if (code == null || !RegExp(r'^\d{8}$').hasMatch(code)) return;
    final now = DateTime.now();
    final previous = _recentFriendLinks[code];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 3)) {
      return;
    }
    _recentFriendLinks[code] = now;
    ref.read(appRouterProvider).go('/friend-room?code=$code');
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start the app-scoped SDK and consent flow before any screen can request ads.
    ref.watch(adMobConsentServiceProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
