import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/format.dart';
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
    final waiting = _withdrawals.where((w) => w.status == 'requested' || w.status == 'sending').toList();
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

/// Add money: choose an amount, pay on Chapa's page (Telebirr, CBE Birr, M-Pesa or card), come back.
class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key, this.suggested});
  final double? suggested;

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.suggested == null ? '' : widget.suggested!.ceil().toString());
  bool _busy = false;
  String? _error;
  Topup? _topup; // set once the payment page has been opened; the screen then waits for the result
  Timer? _poll;
  int _waited = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _amount.dispose();
    super.dispose();
  }

  // Coming back from the payment page: check straight away instead of waiting for the next tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _topup != null && !_topup!.done) _check();
  }

  Future<void> _start() async {
    if (!_form.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final topup = await app.api.startTopup(double.parse(_amount.text.trim()));
      if (!mounted) return;
      setState(() {
        _topup = topup;
        _waited = 0;
      });
      await _openCheckout();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCheckout() async {
    final url = _topup?.checkoutUrl;
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _check() async {
    final id = _topup?.id;
    if (id == null) return;
    _waited += 4;
    try {
      final topup = await context.read<AppState>().api.topupStatus(id);
      if (!mounted) return;
      setState(() => _topup = Topup(id: topup.id, amount: topup.amount, status: topup.status, done: topup.done, checkoutUrl: topup.checkoutUrl ?? _topup?.checkoutUrl));
      if (topup.done || _waited >= 600) _poll?.cancel();
    } catch (_) {
      // Try again at the next tick.
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().config;
    final symbol = config.currencySymbol;
    final topup = _topup;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('top_up'))),
      body: topup != null
          ? _waiting(context, topup, symbol)
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextFormField(
                  controller: _amount,
                  autofocus: widget.suggested == null,
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
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lock_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t('topup_how'), style: Theme.of(context).textTheme.bodySmall)),
                ]),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _start, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.t('continue_to_payment'))),
              ]),
            ),
    );
  }

  Widget _waiting(BuildContext context, Topup topup, String symbol) {
    final scheme = Theme.of(context).colorScheme;
    final failed = topup.done && !topup.succeeded;
    final (icon, color, title, detail) = topup.succeeded
        ? (Icons.check_circle, scheme.primary, context.t('topup_done', {'amount': formatMoney(topup.amount, symbol)}), context.t('topup_done_hint'))
        : failed
            ? (Icons.error_outline, scheme.error, context.t('topup_failed'), context.t('topup_status_failed'))
            : (Icons.open_in_browser, scheme.primary, context.t('finish_payment'), context.t('finish_payment_hint', {'amount': formatMoney(topup.amount, symbol)}));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        if (!topup.done) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: _openCheckout, icon: const Icon(Icons.open_in_new), label: Text(context.t('open_payment_page'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.t('close'))),
        ],
        if (topup.succeeded) FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.t('close'))),
        if (failed) ...[
          FilledButton(
            onPressed: () => setState(() {
              _poll?.cancel();
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

/// Ask for money out of the wallet, to a bank or mobile wallet from Chapa's list.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, required this.available});
  final double available;

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final _name = TextEditingController(text: context.read<AppState>().user?.name ?? '');
  late final _number = TextEditingController(text: (context.read<AppState>().user?.phone ?? '').replaceFirst('+251', '0'));
  List<PayoutBank> _banks = [];
  PayoutBank? _bank;
  bool _loadingBanks = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    setState(() {
      _loadingBanks = true;
      _error = null;
    });
    try {
      final banks = await context.read<AppState>().api.payoutBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _bank = banks.where((b) => b.name.toLowerCase().contains('telebirr')).firstOrNull ?? banks.firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _loadingBanks = false);
    }
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate() || _bank == null) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.requestWithdrawal(amount: double.parse(_amount.text.trim()), bank: _bank!, accountNumber: _number.text.trim(), accountName: _name.text.trim());
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
    final bank = _bank;
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
          if (_loadingBanks) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (!_loadingBanks && _banks.isEmpty) OutlinedButton(onPressed: _loadBanks, child: Text(context.t('retry'))),
          if (_banks.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: bank?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.t('send_money_to')),
              items: [for (final b in _banks) DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))],
              onChanged: (id) => setState(() => _bank = _banks.firstWhere((b) => b.id == id)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.t(bank?.mobile == true ? 'payout_phone' : 'account_number')),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\s'), '');
                if (digits.isEmpty) return context.tr('required');
                final length = bank?.accountLength;
                return length != null && digits.length != length ? context.tr('account_length', {'length': length}) : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.t('account_holder')), validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null),
          ],
          const SizedBox(height: 8),
          Text(context.t('withdraw_note'), style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy || _bank == null ? null : _send, child: Text(context.t('request_withdrawal'))),
        ]),
      ),
    );
  }
}
