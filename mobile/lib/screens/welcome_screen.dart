import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/phone.dart';
import '../l10n/strings.dart';
import '../widgets/common.dart';
import 'code_screen.dart';

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
  String _mode = 'passenger';
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
        final phone = normalizeEthiopianPhone(_email.text)!;
        if (app.config.phoneVerification) {
          // Prove the number first: text a code, then finish on the code screen.
          final sent = await app.api.sendCode(phone);
          if (!mounted) return;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CodeScreen(name: _name.text, phone: phone, password: _password.text, mode: _mode, verificationId: sent.verificationId, codeLength: sent.codeLength)));
        } else {
          await app.signUp(_name.text, phone, _password.text, mode: _mode);
        }
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
              color: brand,
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
                if (_signUp)
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: InputDecoration(labelText: context.t('phone'), hintText: '0911 22 33 44', prefixIcon: const Padding(padding: EdgeInsets.fromLTRB(14, 14, 8, 14), child: Text('🇪🇹 +251', style: TextStyle(fontWeight: FontWeight.w700)))),
                    validator: (v) => normalizeEthiopianPhone(v ?? '') == null ? context.tr('invalid_phone') : null,
                  )
                else
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
                    decoration: InputDecoration(labelText: context.t('phone_or_email'), hintText: '0911 22 33 44', prefixIcon: const Icon(Icons.phone_android)),
                    validator: (v) => isValidLogin(v ?? '') ? null : context.tr('invalid_login'),
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
                if (_signUp) ...[
                  const SizedBox(height: 16),
                  Text(context.t('i_am'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: RoleCard(icon: Icons.airline_seat_recline_normal, title: context.t('role_passenger'), subtitle: context.t('role_passenger_hint'), selected: _mode == 'passenger', onTap: () => setState(() => _mode = 'passenger'))),
                    const SizedBox(width: 10),
                    Expanded(child: RoleCard(icon: Icons.directions_car, title: context.t('role_driver'), subtitle: context.t('role_driver_hint'), selected: _mode == 'driver', onTap: () => setState(() => _mode = 'driver'))),
                  ]),
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.t('role_switch_hint'), style: Theme.of(context).textTheme.bodySmall)),
                ],
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
                    _email.clear();
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

/// A big tappable choice between riding and driving.
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const Spacer(),
              Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 20, color: selected ? scheme.primary : scheme.outlineVariant),
            ]),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
