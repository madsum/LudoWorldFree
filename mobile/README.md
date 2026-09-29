# Ludo World Free (by iProSoft) - Mobile App

Commercial Mobile Game developed with **Flutter** (Material 3), **Clean Architecture**, and **Riverpod** state management. Designed for future integration with a **Java 21 + Spring Boot 3** backend (PostgreSQL, WebSocket, JWT Auth, OAuth2).

---

## 🚀 Features (Part 1 Implementation & Real OAuth Integration)

1. **Splash Screen (`/`)**
   - Full-screen branded splash image (`assets/images/ludo_front_pg.webp`) with no stretching.
   - Smooth 800ms fade-in animation.
   - Displays version text (`Version 1.0.0`) at the bottom while keeping "By iProSoft" visible.
   - Automatically navigates to `/login` after 2 seconds.

2. **Real OAuth Authentication (`/login`)**
   - Premium gaming UI with dark navy gradient and animated floating Ludo pieces background.
   - **Google Sign-In**: Native Google Account Chooser via `google_sign_in` SDK.
   - **Web OAuth 2.0 PKCE Flows**: Real system browser authentication for **GitHub**, **Facebook**, **Apple**, **LinkedIn**, **Microsoft**, and **X (Twitter)** via `flutter_web_auth_2`.
   - Custom URL scheme redirect (`ludoworldfree://oauth-callback`) configured in `AndroidManifest.xml`.
   - Real User Info fetching from provider APIs (Name, Email, Profile ID) and secure token storage via `SecureStorageService`.
   - **Continue as Guest** mode allowing instant guest play.
   - Legal section at bottom with clickable **Terms of Service** and **Privacy Policy** modals.

3. **Home Screen (`/home`)**
   - Custom top app bar displaying player avatar, name (authenticated user or *"Guest Player"*), diamond count (50 💎), gold coin count (2350 🪙), and settings button.
   - Responsive grid of 6 game mode cards:
     - Online Multiplayer
     - Team Up 2v2
     - Play with Friends
     - Vs Computer
     - Pass & Play
     - Tournament
   - Every card displays a **COMING SOON** badge and pleasant notification snackbar.

---

## 🔐 OAuth Configuration (`lib/core/network/oauth_config.dart`)

To configure custom Client IDs for production:
- **Google**: Set `OAuthConfig.googleClientId`
- **GitHub**: Set `OAuthConfig.githubClientId` & `OAuthConfig.githubClientSecret`
- **Facebook**: Set `OAuthConfig.facebookAppId`
- **LinkedIn**: Set `OAuthConfig.linkedinClientId`
- **Microsoft**: Set `OAuthConfig.microsoftClientId`
- **Apple**: Set `OAuthConfig.appleClientId`
- **X (Twitter)**: Set `OAuthConfig.twitterClientId`

---

## 🛠️ Architecture & Tech Stack

```
lib/
 ├── core/
 │    ├── constants/      # Colors, App Constants, Assets
 │    ├── network/        # Dio client, AuthInterceptor, OAuthConfig
 │    ├── storage/        # SecureStorageService for JWT tokens
 │    ├── theme/          # AppTheme with Material 3 & Google Fonts
 │    └── utils/          # Responsive helper for mobile & tablet
 ├── config/              # Environment configuration (dev, staging, prod)
 ├── shared/
 │    └── widgets/        # OAuthButton, CustomGameButton, GlassCard
 ├── features/
 │    ├── splash/         # Splash screen & presentation logic
 │    ├── auth/           # Real OAuth login, Guest login, UserModel, AuthRepository, AuthController
 │    └── home/           # Dashboard, UserProfileBar, MenuCard
 ├── routes/              # GoRouter setup (/ , /login, /home)
 └── main.dart            # Entry point wrapped in ProviderScope
```

---

## 💻 How to Run

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Run Application**
   ```bash
   flutter run
   ```

3. **Run Tests**
   ```bash
   flutter test
   ```
