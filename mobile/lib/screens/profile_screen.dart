import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import '../widgets/paged_trips.dart';
import 'alerts_screen.dart';
import 'driver_setup_screens.dart';
import 'home_shell.dart';
import 'trip_screen.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();
    void push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) => app.refreshUser());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Avatar(user, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if ((user.email ?? '').isNotEmpty) Text(user.email!, style: Theme.of(context).textTheme.bodySmall) else if ((user.phone ?? '').isNotEmpty) Text(user.phone!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                RatingLine(user),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('using_app_as'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'passenger', icon: const Icon(Icons.airline_seat_recline_normal), label: Text(context.t('role_passenger'))),
                  ButtonSegment(value: 'driver', icon: const Icon(Icons.directions_car), label: Text(context.t('role_driver'))),
                ],
                selected: {user.appMode},
                onSelectionChanged: (s) => switchMode(context, s.first),
              ),
            ),
            const SizedBox(height: 6),
            Text(context.t(user.appMode == 'driver' ? 'role_driver_hint' : 'role_passenger_hint'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      _Tile(Icons.edit_outlined, context.t('profile'), () => push(const ProfileFormScreen())),
      if (user.appMode == 'driver') ...[
        _Tile(Icons.directions_car_outlined, context.t('vehicle_details'), () => push(const VehicleScreen()), warn: !user.vehicleComplete),
        _Tile(Icons.account_balance_wallet_outlined, context.t('payment_methods'), () => push(const PaymentMethodsScreen()), warn: user.payments.isEmpty),
        _Tile(Icons.verified_user_outlined, context.t('identity_title'), () => push(const IdentityScreen()), warn: !user.verified),
        _Tile(Icons.route_outlined, context.t('my_trips'), () => push(const MyTripsScreen())),
      ],
      _Tile(Icons.notifications_outlined, context.t('alerts_title'), () => push(const AlertsScreen())),
      Card(
        child: SwitchListTile(
          title: Text(context.t('phone_alerts'), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(context.t('phone_alerts_hint')),
          value: app.phoneAlerts,
          onChanged: app.setPhoneAlerts,
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('appearance'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'system', icon: const Icon(Icons.phone_android), label: Text(context.t('theme_system'))),
                  ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined), label: Text(context.t('theme_light'))),
                  ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined), label: Text(context.t('theme_dark'))),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (s) => app.setThemeMode(s.first),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('language'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'am', label: Text('አማርኛ'))],
              selected: {app.locale},
              onSelectionChanged: (s) => app.setLocale(s.first),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (user.isStaff) _Tile(Icons.admin_panel_settings_outlined, context.t('admin_web'), () => launchUrl(Uri.parse('$apiBase/admin'), mode: LaunchMode.externalApplication)),
      _Tile(Icons.logout, context.t('sign_out'), () => app.signOut()),
      const SizedBox(height: 4),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
        onPressed: () async {
          if (await confirmDialog(context, context.tr('delete_account_confirm'), action: context.tr('delete'))) {
            try {
              await app.deleteAccount();
            } catch (e) {
              if (context.mounted) showMessage(context, errorText(context, e), error: true);
            }
          }
        },
        child: Text(context.t('delete_account')),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.label, this.onTap, {this.warn = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: warn ? const Icon(Icons.error_outline, color: Color(0xFFB8860B)) : const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      );
}

class MyTripsScreen extends StatelessWidget {
  const MyTripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('my_trips'))),
      body: PagedTrips(loader: (page) => app.api.myTrips(page: page), onOpen: (t) => openTrip(context, t.id), showDriver: false, emptyText: context.t('no_trips')),
    );
  }
}

/// Phone number, fuel cost and email preference.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  late final _phone = TextEditingController(text: context.read<AppState>().user?.phone ?? '');
  late bool _email = context.read<AppState>().user?.sendEmail ?? false;
  late final bool _phoneAccount = context.read<AppState>().user?.phoneAccount ?? false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      app.updateUser(await app.api.updateMe({
        if (!_phoneAccount) 'phone': _phone.text.trim(),
        if (!_phoneAccount) 'send_email_messages': _email,
      }));
      if (mounted) {
        showMessage(context, context.tr('saved'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('profile'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _phone, enabled: !_phoneAccount, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.t('phone'), helperText: context.t(_phoneAccount ? 'phone_is_login' : 'phone_hint'), helperMaxLines: 3)),
          if (!_phoneAccount) SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('email_notifications')), value: _email, onChanged: (v) => setState(() => _email = v)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: Text(context.t('save'))),
        ]),
      );
}

/// The vehicle questions the super admin configured (make, colour, plate, ...).
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _values = Map<String, dynamic>.from(context.read<AppState>().user?.vehicleData ?? const {});
  final Map<String, TextEditingController> _controllers = {};
  bool _busy = false;

  TextEditingController _controller(VehicleField f) => _controllers.putIfAbsent(f.key, () => TextEditingController(text: '${_values[f.key] ?? ''}'));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{};
      for (final f in app.config.vehicleFields) {
        if (f.type == 'boolean') {
          data[f.key] = _values[f.key] == true ? '1' : '0';
        } else if (f.type == 'select') {
          data[f.key] = '${_values[f.key] ?? ''}';
        } else {
          data[f.key] = _controller(f).text.trim();
        }
      }
      app.updateUser(await app.api.updateMe({'vehicle_data': data}));
      if (mounted) {
        showMessage(context, context.tr('saved'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _visibility(BuildContext context, String v) => switch (v) {
        'confirmed' => context.t('visible_confirmed'),
        'private' => context.t('visible_private'),
        _ => context.t('visible_all'),
      };

  @override
  Widget build(BuildContext context) {
    final fields = context.watch<AppState>().config.vehicleFields;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('vehicle_details'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(context.t('vehicle_intro')),
          const SizedBox(height: 16),
          for (final f in fields) ...[
            _field(context, f),
            const SizedBox(height: 14),
          ],
          FilledButton(onPressed: _busy ? null : _save, child: Text(context.t('save'))),
        ]),
      ),
    );
  }

  Widget _field(BuildContext context, VehicleField f) {
    final label = f.required ? '${f.label} *' : f.label;
    final helper = [if ((f.helpText ?? '').isNotEmpty) f.helpText!, _visibility(context, f.visibility)].join(' · ');
    String? requiredCheck(String? v) => f.required && (v ?? '').trim().isEmpty ? context.tr('required') : null;
    switch (f.type) {
      case 'select':
        final current = '${_values[f.key] ?? ''}';
        return DropdownButtonFormField<String>(
          initialValue: f.options.contains(current) ? current : null,
          decoration: InputDecoration(labelText: label, helperText: helper),
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
          validator: requiredCheck,
          onChanged: (v) => _values[f.key] = v,
        );
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(helper),
          value: _values[f.key] == true || _values[f.key] == '1' || _values[f.key] == 'true',
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case 'number':
        return TextFormField(
          controller: _controller(f),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, helperText: helper),
          validator: (v) {
            final base = requiredCheck(v);
            if (base != null) return base;
            if ((v ?? '').trim().isEmpty) return null;
            final n = num.tryParse(v!.trim());
            if (n == null) return context.tr('required');
            if ((f.min != null && n < f.min!) || (f.max != null && n > f.max!)) return '${f.min ?? ''}–${f.max ?? ''}';
            return null;
          },
        );
      default:
        return TextFormField(controller: _controller(f), decoration: InputDecoration(labelText: label, helperText: helper), validator: requiredCheck);
    }
  }
}
