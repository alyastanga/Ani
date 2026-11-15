import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_shell.dart';
import 'app_state.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'l10n/app_localizations.dart';
import 'theme/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AniApp());
}

/// Root widget. Pass [state] to inject an [AppState] (tests); otherwise one
/// is created and initialised from saved settings.
class AniApp extends StatefulWidget {
  const AniApp({super.key, this.state});

  final AppState? state;

  @override
  State<AniApp> createState() => _AniAppState();
}

class _AniAppState extends State<AniApp> {
  late final AppState _state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    if (widget.state == null) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          theme: AniTheme.light(),
          locale: _state.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _Root(),
        ),
      ),
    );
  }
}

/// Chooses splash / onboarding / error / shell from [AppState].
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.initialized) return const _Splash();
    if (!state.onboardingComplete) return const OnboardingScreen();
    if (state.bundle != null) return const AppShell();
    if (state.bundleError != null) return _BundleError(state: state);
    return const _Splash();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: ValueKey('splash'),
      backgroundColor: AniColors.cream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ani',
              style: TextStyle(
                fontFamily: aniFontFamily,
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: AniColors.olive,
              ),
            ),
            SizedBox(height: AniSpacing.lg),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: AniColors.olive),
            ),
          ],
        ),
      ),
    );
  }
}

class _BundleError extends StatelessWidget {
  const _BundleError({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('bundle-error'),
      backgroundColor: AniColors.cream,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AniSpacing.xxl),
            child: AniCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.error_outline, color: AniColors.statusDelikado, size: 32),
                  const SizedBox(height: AniSpacing.md),
                  Text(
                    l.bundleLoadError,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (state.town != null) ...[
                    const SizedBox(height: AniSpacing.xs),
                    Text(
                      state.town!.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AniColors.muted),
                    ),
                  ],
                  const SizedBox(height: AniSpacing.lg),
                  PrimaryButton(
                    label: l.actionRetry,
                    icon: Icons.refresh,
                    onPressed: state.bundleLoading ? null : state.retryBundle,
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
