import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Conversation> _items = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final data = await app.api.conversations();
      if (mounted) {
        setState(() {
          _items = data.items;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<AppState>().locale;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('messages'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(_error!, onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: [const SizedBox(height: 80), EmptyState(context.t('no_messages'), icon: Icons.chat_bubble_outline)])
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = _items[i];
                            return ListTile(
                              leading: Avatar(c.with_, size: 44),
                              title: Text(c.with_.name, style: TextStyle(fontWeight: c.unread ? FontWeight.w800 : FontWeight.w600)),
                              subtitle: Text(c.last?.body ?? c.tripTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (c.last?.createdAt != null) Text(formatDate(c.last!.createdAt!, locale: locale), style: Theme.of(context).textTheme.bodySmall),
                                if (c.unread) const Padding(padding: EdgeInsets.only(top: 4), child: CircleAvatar(radius: 5, backgroundColor: brand)),
                              ]),
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: c.id, title: c.with_.name)));
                                _load();
                              },
                            );
                          },
                        ),
                ),
    );
  }
}
