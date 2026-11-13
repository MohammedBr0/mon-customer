import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/phone.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// The wallet: balance, money set aside, adding money, asking for money out, and the history.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletBalance _balance = const WalletBalance();
  List<WalletEntry> _entries = [];
  List<Withdrawal> _withdrawals = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AppState>().api.wallet();
      if (!mounted) return;
      setState(() {
        _balance = data.balance;
        _entries = data.entries;
        _withdrawals = data.withdrawals;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _topUp() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const TopUpScreen()));
    if (added == true) _load();
  }

  Future<void> _withdraw() async {
    final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => WithdrawScreen(available: _balance.available)));
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final symbol = app.config.currencySymbol;
    final waiting = _withdrawals.where((w) => w.status == 'requested').toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('wallet'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _entries.isEmpty
              ? ErrorState(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(20)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t('wallet_available').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(formatMoney(_balance.available, symbol), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
                        if (_balance.held > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text(context.t('wallet_held', {'amount': formatMoney(_balance.held, symbol)}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brand, minimumSize: const Size.fromHeight(46)),
                              onPressed: app.config.walletEnabled ? _topUp : null,
                              icon: const Icon(Icons.add),
                              label: Text(context.t('top_up')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white), minimumSize: const Size.fromHeight(46)),
                              onPressed: _balance.available >= app.config.minWithdrawal ? _withdraw : null,
                              icon: const Icon(Icons.north_east),
                              label: Text(context.t('withdraw')),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                    if (!app.config.walletEnabled) Padding(padding: const EdgeInsets.only(top: 10), child: Text(context.t('wallet_off'), style: TextStyle(color: scheme.onSurfaceVariant))),
                    if (waiting.isNotEmpty) ...[
                      SectionTitle(context.t('withdrawals_waiting')),
                      for (final w in waiting)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.hourglass_top),
                              title: Text(formatMoney(w.amount, symbol), style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text('${w.methodName} · ${w.accountNumber}'),
                            ),
                          ),
                        ),
                    ],
                    SectionTitle(context.t('wallet_history')),
                    if (_entries.isEmpty) EmptyState(context.t('wallet_empty'), icon: Icons.account_balance_wallet_outlined),
                    for (final e in _entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: e.amount >= 0 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                          child: Icon(e.amount >= 0 ? Icons.south_west : Icons.north_east, size: 18, color: e.amount >= 0 ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                        ),
                        title: Text(context.t('entry_${e.kind}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([if ((e.memo ?? '').isNotEmpty) e.memo!, if (e.createdAt != null) formatDateTime(e.createdAt!, locale: app.locale)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text('${e.amount >= 0 ? '+' : '−'}${formatMoney(e.amount.abs(), symbol)}', style: TextStyle(fontWeight: FontWeight.w800, color: e.amount >= 0 ? scheme.primary : scheme.onSurface)),
                      ),
                  ]),
                ),
    );
  }
}

String providerLabel(String key) => switch (key) { 'telebirr' => 'Telebirr', 'cbe_birr' => 'CBE Birr', 'mpesa' => 'M-Pesa', 'awash_birr' => 'Awash Birr', _ => key };

/// Add money: choose an amount and a provider, then approve the PIN prompt that appears on the phone.
class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key, this.suggested});
  final double? suggested;

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.suggested == null ? '' : widget.suggested!.ceil().toString());
  late final _phone = TextEditingController(text: (context.read<AppState>().user?.phone ?? '').replaceFirst('+251', '0'));
  late String _provider = context.read<AppState>().config.walletProviders.firstOrNull ?? 'telebirr';
  bool _busy = false;
  String? _error;
  Topup? _topup; // set once the prompt has been sent; the screen then waits for the result
  Timer? _poll;
  int _waited = 0;

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final topup = await app.api.startTopup(amount: double.parse(_amount.text.trim()), provider: _provider, phone: normalizeEthiopianPhone(_phone.text)!);
      if (!mounted) return;
      setState(() {
        _topup = topup;
        _waited = 0;
      });
      // The provider tells the server the result; ask the server every few seconds until it is known.
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final id = _topup?.id;
    if (id == null) return;
    _waited += 3;
    try {
      final topup = await context.read<AppState>().api.topupStatus(id);
      if (!mounted) return;
      setState(() => _topup = topup);
      if (topup.done || _waited >= 180) _poll?.cancel();
    } catch (_) {
      // Try again at the next tick.
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final config = app.config;
    final symbol = config.currencySymbol;
    final topup = _topup;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('top_up'))),
      body: topup != null ? _waiting(context, topup, symbol) : Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: context.t('amount'), prefixText: '$symbol '),
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              return n == null || n < config.minTopup || n > config.maxTopup ? context.tr('amount_between', {'min': config.minTopup.round(), 'max': config.maxTopup.round()}) : null;
            },
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final quick in const [100, 200, 500, 1000]) ActionChip(label: Text('$quick'), onPressed: () => setState(() => _amount.text = '$quick')),
          ]),
          const SizedBox(height: 16),
          Text(context.t('pay_with_provider'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in config.walletProviders) ChoiceChip(label: Text(providerLabel(p)), selected: _provider == p, onSelected: (_) => setState(() => _provider = p)),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.t('paying_phone'), helperText: context.t('paying_phone_hint'), helperMaxLines: 2, prefixIcon: const Icon(Icons.phone_android)),
            validator: (v) => normalizeEthiopianPhone(v ?? '') == null ? context.tr('invalid_phone') : null,
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _start, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.t('send_payment_prompt'))),
        ]),
      ),
    );
  }

  Widget _waiting(BuildContext context, Topup topup, String symbol) {
    final scheme = Theme.of(context).colorScheme;
    final failed = topup.done && !topup.succeeded;
    final timedOut = !topup.done && _waited >= 180;
    final (icon, color, title, detail) = topup.succeeded
        ? (Icons.check_circle, scheme.primary, context.t('topup_done', {'amount': formatMoney(topup.amount, symbol)}), context.t('topup_done_hint'))
        : failed
            ? (Icons.error_outline, scheme.error, context.t('topup_failed'), context.t('topup_status_${topup.status}'))
            : timedOut
                ? (Icons.schedule, scheme.onSurfaceVariant, context.t('topup_slow'), context.t('topup_slow_hint'))
                : (Icons.phone_android, scheme.primary, context.t('check_your_phone'), context.t('check_your_phone_hint', {'amount': formatMoney(topup.amount, symbol), 'provider': providerLabel(_provider)}));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        if (!topup.done && !timedOut) const Center(child: CircularProgressIndicator()),
        if (topup.succeeded || timedOut) FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.t('close'))),
        if (failed) ...[
          FilledButton(
            onPressed: () => setState(() {
              _topup = null;
              _error = null;
            }),
            child: Text(context.t('retry')),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.t('close'))),
        ],
      ]),
    );
  }
}

/// Ask for money out of the wallet. An admin sends it and marks it done.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, required this.available});
  final double available;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final List<DriverPayment> _accounts = [for (final p in context.read<AppState>().user?.payments ?? const <DriverPayment>[]) if ((p.accountNumber ?? '').isNotEmpty) p];
  late DriverPayment? _account = _accounts.firstOrNull;
  final _method = TextEditingController();
  final _number = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.requestWithdrawal(
        amount: double.parse(_amount.text.trim()),
        methodName: _account?.name ?? _method.text.trim(),
        accountNumber: _account?.accountNumber ?? _number.text.trim(),
        accountName: _account?.accountName,
      );
      if (mounted) {
        showMessage(context, context.tr('withdrawal_requested'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().config;
    final symbol = config.currencySymbol;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('withdraw'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(context.t('withdraw_available', {'amount': formatMoney(widget.available, symbol)}), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: context.t('amount'), prefixText: '$symbol '),
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              return n == null || n < config.minWithdrawal || n > widget.available ? context.tr('amount_between', {'min': config.minWithdrawal.round(), 'max': widget.available.floor()}) : null;
            },
          ),
          const SizedBox(height: 16),
          Text(context.t('send_money_to'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_accounts.isNotEmpty)
            RadioGroup<DriverPayment?>(
              groupValue: _account,
              onChanged: (v) => setState(() => _account = v),
              child: Column(children: [
                for (final a in _accounts) RadioListTile<DriverPayment?>(contentPadding: EdgeInsets.zero, value: a, title: Text(a.name), subtitle: Text(a.accountNumber!)),
                RadioListTile<DriverPayment?>(contentPadding: EdgeInsets.zero, value: null, title: Text(context.t('another_account'))),
              ]),
            ),
          if (_account == null) ...[
            TextFormField(controller: _method, decoration: InputDecoration(labelText: context.t('payout_method'), hintText: 'Telebirr'), validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null),
            const SizedBox(height: 10),
            TextFormField(controller: _number, decoration: InputDecoration(labelText: context.t('account_number')), validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null),
          ],
          const SizedBox(height: 8),
          Text(context.t('withdraw_note'), style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _send, child: Text(context.t('request_withdrawal'))),
        ]),
      ),
    );
  }
}
