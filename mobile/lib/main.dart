import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/app_state.dart';
import 'core/phone_notifier.dart';
import 'core/token_store.dart';
import 'screens/home_shell.dart';
import 'screens/welcome_screen.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  await initializeDateFormatting('am');
  final state = AppState(api: Api(), store: const SecureTokenStore(), notifier: LocalPhoneNotifier());
  runApp(IcareApp(state: state));
  state.start();
}

class IcareApp extends StatelessWidget {
  const IcareApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          title: 'icare',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: const _Root(),
        ),
      );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, AuthStatus>((s) => s.status);
    return switch (status) {
      AuthStatus.starting => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.signedOut => const WelcomeScreen(),
      AuthStatus.offline => const OfflineScreen(),
      AuthStatus.signedIn => const HomeShell(),
    };
  }
}
