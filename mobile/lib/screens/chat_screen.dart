import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// A conversation. Open it with [conversationId], or with [tripId] to message a trip's driver for the first time.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.conversationId, this.tripId, required this.title});
  final int? conversationId;
  final int? tripId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Conversation? _conversation;
  late int? _id = widget.conversationId;
  bool _loading = true;
  bool _sending = false;
  Object? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (_id != null) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(quiet: true));
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final app = context.read<AppState>();
    try {
      final c = await app.api.conversation(_id!);
      if (!mounted) return;
      final grew = c.messages.length != (_conversation?.messages.length ?? -1);
      setState(() {
        _conversation = c;
        _error = null;
        _loading = false;
      });
      if (grew) _toBottom();
    } catch (e) {
      if (mounted && !quiet) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    final app = context.read<AppState>();
    setState(() => _sending = true);
    try {
      final c = _id == null ? await app.api.startConversation(widget.tripId!, body) : await app.api.sendMessage(_id!, body);
      _input.clear();
      if (!mounted) return;
      setState(() {
        _conversation = c;
        _id = c.id;
      });
      _poll ??= Timer.periodic(const Duration(seconds: 8), (_) => _load(quiet: true));
      _toBottom();
    } catch (e) {
      if (mounted) showMessage(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.user?.id;
    final messages = _conversation?.messages ?? const <Message>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(_error!, onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    })
                  : messages.isEmpty
                      ? EmptyState(context.t('send_first_message'), icon: Icons.chat_bubble_outline)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (_, i) => _Bubble(message: messages[i], mine: messages[i].senderId == me, locale: app.locale),
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: context.t('message_hint'), counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: context.t('send'),
                onPressed: _sending ? null : _send,
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.locale});
  final Message message;
  final bool mine;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(message.body, style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface)),
          if (message.createdAt != null)
            Text(formatDateTime(message.createdAt!, locale: locale), style: TextStyle(fontSize: 11, color: (mine ? scheme.onPrimary : scheme.onSurface).withValues(alpha: 0.7))),
        ]),
      ),
    );
  }
}
