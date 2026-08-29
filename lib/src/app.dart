import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import 'data/account_repository.dart';
import 'data/catalog_repository.dart';
import 'data/inventory_repository.dart';
import 'data/paint_list_repository.dart';
import 'data/published_recipe_repository.dart';
import 'data/recipe_photo_repository.dart';
import 'data/recipe_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/sample_recipe_seeder.dart';
import 'state/inventory_provider.dart';
import 'state/paint_lists_provider.dart';
import 'state/follows_provider.dart';
import 'state/recipes_provider.dart';
import 'theme.dart';
import 'widgets/brand_loader.dart';

class PintaMinisApp extends StatelessWidget {
  const PintaMinisApp({
    super.key,
    required this.catalog,
    required this.settings,
    required this.firebaseReady,
  });

  final CatalogRepository catalog;
  final AppSettings settings;
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CatalogRepository>.value(value: catalog),
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        if (firebaseReady)
          Provider<AuthService>(create: (_) => FirebaseAuthService()),
      ],
      child: firebaseReady
          ? const _AuthGate()
          : const _PintaMinisMaterialApp(
              key: ValueKey('setup'),
              home: FirebaseSetupScreen(),
            ),
    );
  }
}

/// The single [MaterialApp] for the app, parameterised by whatever screen the
/// auth state calls for.
///
/// Every user-scoped provider is mounted ABOVE this widget on purpose: a
/// provider placed inside `home:` would sit below the root Navigator, and
/// then every pushed route and modal sheet would fail with
/// ProviderNotFoundException. See test/provider_scope_test.dart.
class _PintaMinisMaterialApp extends StatelessWidget {
  const _PintaMinisMaterialApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    // watch, not read: switching the language in Settings must rebuild the
    // whole tree, and this widget is the highest point below the provider.
    final locale =
        context.watch<AppSettings?>()?.localeOverride;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      theme: PintaMinisTheme.light(),
      darkTheme: PintaMinisTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }
}

/// Shows the login screen or the app depending on the auth state, wrapping the
/// signed-in case with the user-scoped providers.
///
/// Every branch gives [_PintaMinisMaterialApp] a DIFFERENT key on purpose.
/// Without one, the MaterialApp is the same widget type across branches, so
/// Flutter updates it in place and the Navigator keeps its existing route
/// stack — swapping `home:` then only replaces the route *underneath*
/// whatever is pushed on top. Signing out from the pushed Settings screen
/// would leave the user staring at Settings as if the button did nothing.
/// See test/auth_gate_test.dart.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return StreamBuilder<User?>(
      // userChanges, not authStateChanges: the latter never fires when the
      // profile picture finishes loading, so the avatar stayed a gear.
      stream: auth.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PintaMinisMaterialApp(
            key: ValueKey('loading'),
            home: _LoadingScreen(),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const _PintaMinisMaterialApp(
            key: ValueKey('signed-out'),
            home: LoginScreen(),
          );
        }
        // Keyed by uid so switching account tears down the old user's
        // streams instead of leaking them into the new session.
        final recipeRepository = FirestoreRecipeRepository(uid: user.uid);
        final publishedRepository =
            FirestorePublishedRecipeRepository(uid: user.uid);
        final photoRepository =
            FirebaseRecipePhotoRepository(uid: user.uid);
        return MultiProvider(
          key: ValueKey(user.uid),
          providers: [
            ChangeNotifierProvider<InventoryProvider>(
              create: (_) => InventoryProvider(
                repository: FirestoreInventoryRepository(uid: user.uid),
              ),
            ),
            ChangeNotifierProvider<PaintListsProvider>(
              create: (_) => PaintListsProvider(
                repository: FirestorePaintListRepository(uid: user.uid),
              ),
            ),
            Provider<PublishedRecipeRepository>.value(
              value: publishedRepository,
            ),
            Provider<RecipePhotoRepository>.value(value: photoRepository),
            ChangeNotifierProvider<FollowsProvider>(
              create: (_) =>
                  FollowsProvider(repository: publishedRepository),
            ),
            ChangeNotifierProvider<RecipesProvider>(
              create: (_) => RecipesProvider(
                repository: recipeRepository,
                publishedRepository: publishedRepository,
                photoRepository: photoRepository,
                // Public name shown on shared recipes.
                authorName: () =>
                    user.displayName ??
                    user.email?.split('@').first ??
                    'Anonymous painter',
                // Through the service, not the captured user: the getter
                // also checks providerData, where Google parks the photo.
                authorPhotoUrl: () => auth.photoUrl,
              ),
            ),
            Provider<SampleRecipeSeeder>(
              create: (_) => SampleRecipeSeeder(
                uid: user.uid,
                recipes: recipeRepository,
              ),
            ),
            Provider<AccountRepository>(
              create: (_) => FirestoreAccountRepository(
                uid: user.uid,
                photos: photoRepository,
              ),
            ),
          ],
          child: _PintaMinisMaterialApp(
            key: ValueKey('signed-in-${user.uid}'),
            home: const HomeScreen(),
          ),
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    // No delay here: this IS the app starting up, so there is no risk of
    // flashing over content that was already on screen.
    return const Scaffold(
      body: Center(child: BrandLoader(delay: Duration.zero)),
    );
  }
}

/// Shown when the app is built without Firebase configuration.
class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department, size: 64),
              const SizedBox(height: 16),
              Text(
                l10n.firebaseSetupTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.firebaseSetupBody,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
