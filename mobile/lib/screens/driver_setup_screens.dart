import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/phone.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// A driver ticks the payment methods they accept (from the admins' list) and adds the account to pay into.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final _form = GlobalKey<FormState>();
  final Set<int> _chosen = {};
  final Map<int, TextEditingController> _names = {};
  final Map<int, TextEditingController> _numbers = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final p in context.read<AppState>().user?.payments ?? const <DriverPayment>[]) {
      _chosen.add(p.id);
      _names[p.id] = TextEditingController(text: p.accountName ?? '');
      _numbers[p.id] = TextEditingController(text: p.accountNumber ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in [..._names.values, ..._numbers.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _name(int id) => _names.putIfAbsent(id, TextEditingController.new);
  TextEditingController _number(int id) => _numbers.putIfAbsent(id, TextEditingController.new);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final options = app.config.paymentMethods.where((o) => _chosen.contains(o.id));
      app.updateUser(await app.api.savePaymentMethods([
        for (final o in options) DriverPayment(id: o.id, name: o.name, accountName: o.needsAccount ? _name(o.id).text.trim() : null, accountNumber: o.needsAccount ? _number(o.id).text.trim() : null),
      ]));
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
  Widget build(BuildContext context) {
    final options = context.watch<AppState>().config.paymentMethods;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('payment_methods'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(context.t('payment_methods_intro')),
          const SizedBox(height: 12),
          if (options.isEmpty) EmptyState(context.t('no_payment_methods'), icon: Icons.account_balance_wallet_outlined),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Column(children: [
                  CheckboxListTile(
                    value: _chosen.contains(option.id),
                    title: Text(option.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    onChanged: (on) => setState(() => on == true ? _chosen.add(option.id) : _chosen.remove(option.id)),
                  ),
                  if (_chosen.contains(option.id) && option.needsAccount)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(children: [
                        TextFormField(
                          controller: _number(option.id),
                          decoration: InputDecoration(labelText: option.accountLabel ?? context.t('account_number')),
                          validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(controller: _name(option.id), textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.t('account_name'))),
                      ]),
                    ),
                ]),
              ),
            ),
          Text(context.t('payment_privacy'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(context.t('save'))),
        ]),
      ),
    );
  }
}

/// A driver sends photos of their driving licence and national ID; staff check them and the badge follows.
class IdentityScreen extends StatelessWidget {
  const IdentityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().user;
    final docs = {for (final d in user?.identity ?? const <IdentityDoc>[]) d.kind: d};
    return Scaffold(
      appBar: AppBar(title: Text(context.t('identity_title'))),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await context.read<AppState>().refreshUser();
          } catch (_) {}
        },
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(user?.verified == true ? Icons.verified : Icons.shield_outlined, color: Theme.of(context).colorScheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(context.t(user?.verified == true ? 'identity_verified' : (context.watch<AppState>().driverMode ? 'identity_intro' : 'identity_intro_passenger')))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        // Everyone proves who they are with their national ID; drivers also send their driving licence.
        for (final kind in ['national_id', if (context.watch<AppState>().driverMode) 'driver_license']) ...[
          _DocumentCard(kind: kind, doc: docs[kind]),
          const SizedBox(height: 12),
        ],
        Text(context.t('identity_privacy'), style: Theme.of(context).textTheme.bodySmall),
      ]),
      ),
    );
  }
}

class _DocumentCard extends StatefulWidget {
  const _DocumentCard({required this.kind, this.doc});
  final String kind;
  final IdentityDoc? doc;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  late final _number = TextEditingController(text: widget.doc?.number ?? '');
  XFile? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // Shrunk on the phone so the upload is quick on a slow connection and the text stays readable.
      final photo = await ImagePicker().pickImage(source: source, maxWidth: 1800, maxHeight: 1800, imageQuality: 72);
      if (photo != null && mounted) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('photo_failed'));
    }
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    if (_number.text.trim().isEmpty || _photo == null) {
      setState(() => _error = context.tr('identity_need_both'));
      return;
    }
    if (widget.kind == 'national_id' && !isFan(_number.text)) {
      setState(() => _error = context.tr('fan_invalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _photo!.readAsBytes();
      app.updateUser(await app.api.submitIdentity(kind: widget.kind, number: _number.text.trim(), imageBytes: bytes, filename: _photo!.name));
      if (mounted) {
        setState(() => _photo = null);
        showMessage(context, context.tr('identity_sent'));
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = widget.doc?.status ?? 'missing';
    final approved = status == 'approved';
    final (icon, color) = switch (status) {
      'approved' => (Icons.check_circle, scheme.primary),
      'pending' => (Icons.hourglass_top, const Color(0xFFB8860B)),
      'rejected' => (Icons.error_outline, scheme.error),
      _ => (Icons.upload_file_outlined, scheme.onSurfaceVariant),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(widget.kind == 'driver_license' ? Icons.badge_outlined : Icons.credit_card, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(context.t('doc_${widget.kind}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 4),
            Text(context.t('doc_status_$status'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ]),
          if (status == 'rejected' && (widget.doc?.rejectionReason ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.doc!.rejectionReason!, style: TextStyle(color: scheme.error))),
          if (status == 'pending') Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.t('identity_pending_hint'), style: Theme.of(context).textTheme.bodySmall)),
          if (!approved) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: widget.kind == 'national_id' ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                labelText: context.t(widget.kind == 'national_id' ? 'fan_number' : 'doc_number'),
                hintText: widget.kind == 'national_id' ? '1234 5678 9012 3456' : null,
                helperText: widget.kind == 'national_id' ? context.t('fan_hint') : null,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: Text(context.t('take_photo')))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(context.t('choose_photo')))),
            ]),
            if (_photo != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.image_outlined, size: 18, color: scheme.primary), const SizedBox(width: 6), Expanded(child: Text(_photo!.name, maxLines: 1, overflow: TextOverflow.ellipsis))])),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: scheme.error))),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.t(status == 'missing' ? 'send_for_review' : 'send_again')),
            ),
          ],
        ]),
      ),
    );
  }
}
