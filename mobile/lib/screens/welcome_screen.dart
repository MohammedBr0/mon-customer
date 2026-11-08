import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../widgets/common.dart';

/// Sign in or create an account. Credentials go to the icare server, which checks them with Neon Auth.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await app.signUp(_name.text, _email.text, _password.text);
      } else {
        await app.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B7A4B), Color(0xFF0A5C3A)]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('icare', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(foregroundColor: Colors.white, selectedForegroundColor: brand, selectedBackgroundColor: Colors.white, visualDensity: VisualDensity.compact),
                  segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'am', label: Text('አማ'))],
                  selected: {app.locale},
                  onSelectionChanged: (s) => app.setLocale(s.first),
                ),
              ]),
              const SizedBox(height: 28),
              Text(context.t('tagline'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 10),
              Text(context.t('tagline_sub'), style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 16)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_signUp ? context.t('sign_up') : context.t('sign_in'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                if (_signUp) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: InputDecoration(labelText: context.t('name')),
                    validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: context.t('email')),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : context.tr('invalid_email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: context.t('password'),
                    helperText: _signUp ? context.t('password_hint') : null,
                    suffixIcon: IconButton(icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _hidePassword = !_hidePassword)),
                  ),
                  validator: (v) => (v ?? '').length < 8 ? context.tr('password_short') : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                    child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(_signUp ? context.t('sign_up') : context.t('sign_in')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _signUp = !_signUp;
                    _error = null;
                  }),
                  child: Text(_signUp ? context.t('have_account') : context.t('no_account')),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Shown when the phone is offline at start-up and a saved sign-in exists.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: EmptyState(
            context.t('error_network'),
            icon: Icons.cloud_off_outlined,
            action: FilledButton(onPressed: () => context.read<AppState>().start(), child: Text(context.t('retry'))),
          ),
        ),
      );
}
