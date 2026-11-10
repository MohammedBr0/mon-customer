import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../widgets/common.dart';

/// The last step of registering with a phone number: type the code that was sent by SMS.
class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key, required this.name, required this.phone, required this.password, required this.mode, required this.verificationId, this.codeLength = 6});
  final String name;
  final String phone;
  final String password;
  final String mode;
  final String verificationId;
  final int codeLength;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _wait = 60;
  final _code = TextEditingController();
  late String _verificationId = widget.verificationId;
  bool _busy = false;
  String? _error;
  int _seconds = _wait;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _countDown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _countDown() {
    _timer?.cancel();
    setState(() => _seconds = _wait);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _seconds--);
      if (_seconds <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    if (_code.text.length != widget.codeLength || _busy) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.signUp(widget.name, widget.phone, widget.password, mode: widget.mode, verificationId: _verificationId, code: _code.text);
      // Signed in: the app's root now shows the home screen, so this screen just steps aside.
      if (mounted) navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final app = context.read<AppState>();
    setState(() => _error = null);
    try {
      final sent = await app.api.sendCode(widget.phone);
      if (!mounted) return;
      _verificationId = sent.verificationId;
      _code.clear();
      _countDown();
      showMessage(context, context.tr('code_resent'));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('enter_code'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.sms_outlined, size: 56, color: scheme.primary),
        const SizedBox(height: 16),
        Text(context.t('code_sent_to', {'length': widget.codeLength, 'phone': widget.phone}), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: widget.codeLength,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 10),
          decoration: InputDecoration(labelText: context.t('code'), counterText: ''),
          onChanged: (v) {
            setState(() {});
            if (v.length == widget.codeLength) _submit();
          },
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
          onPressed: _busy || _code.text.length != widget.codeLength ? null : _submit,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(context.t('verify_and_create')),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _seconds > 0 || _busy ? null : _resend, child: Text(_seconds > 0 ? context.t('resend_in', {'seconds': _seconds}) : context.t('resend_code'))),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(context.t('wrong_number'))),
      ]),
    );
  }
}
