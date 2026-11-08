import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../l10n/strings.dart';
import '../widgets/common.dart';
import 'package:provider/provider.dart';

const reportReasons = ['unsafe_driving', 'fake_or_scam', 'harassment', 'wrong_information', 'no_show', 'inappropriate', 'other'];

/// Asks for a star rating and an optional comment, then sends the review.
Future<bool> showReviewDialog(BuildContext context, {required int bookingId, required bool ofDriver}) async {
  final app = context.read<AppState>();
  var rating = 5;
  final comment = TextEditingController();
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ctx.tr(ofDriver ? 'rate_driver' : 'rate_passenger'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 38,
                tooltip: '$i',
                onPressed: () => setSheet(() => rating = i),
                icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFB8860B)),
              ),
          ]),
          TextField(controller: comment, maxLines: 3, maxLength: 1000, decoration: InputDecoration(labelText: ctx.tr('comment'))),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              try {
                await app.api.review(bookingId, rating, comment.text.trim());
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) showMessage(ctx, errorText(ctx, e), error: true);
              }
            },
            child: Text(ctx.tr('send_review')),
          ),
        ]),
      ),
    ),
  );
  comment.dispose();
  if (sent == true && context.mounted) showMessage(context, context.tr('review_sent'));
  return sent ?? false;
}

/// Lets a person report a trip or a person to the moderators.
Future<void> showReportDialog(BuildContext context, {required String type, required int id}) async {
  final app = context.read<AppState>();
  var reason = reportReasons.first;
  final details = TextEditingController();
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ctx.tr('report_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: reason,
            decoration: InputDecoration(labelText: ctx.tr('report_reason')),
            items: [for (final r in reportReasons) DropdownMenuItem(value: r, child: Text(ctx.tr('reason_$r')))],
            onChanged: (v) => setSheet(() => reason = v ?? reason),
          ),
          const SizedBox(height: 12),
          TextField(controller: details, maxLines: 4, maxLength: 1000, decoration: InputDecoration(labelText: ctx.tr('report_details'))),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              try {
                await app.api.report(type, id, reason, details.text.trim());
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) showMessage(ctx, errorText(ctx, e), error: true);
              }
            },
            child: Text(ctx.tr('report')),
          ),
        ]),
      ),
    ),
  );
  details.dispose();
  if (sent == true && context.mounted) showMessage(context, context.tr('report_sent'));
}
