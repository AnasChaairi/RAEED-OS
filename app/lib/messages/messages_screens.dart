import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/session_scope.dart';
import '../instructor/models.dart';
import '../instructor/widgets.dart';
import '../notifications/inbox.dart';
import '../notifications/push.dart';
import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'messages_repository.dart';

String _when(DateTime t) => '${longDay(t)} ${formatTime(t.hour * 60 + t.minute)}';

/// Loads messages, reloads on pull and when a notification arrives, and shows them.
mixin _MessagesLoader<T extends StatefulWidget> on State<T> {
  Future<List<ChildMessage>>? items;
  StreamSubscription<PushMessage>? _pushes;

  /// The children to load for, or null for every one the person may read.
  List<String>? get childIds;

  MessagesRepository? get repo => MessagesScope.of(context);

  void reload() {
    final r = repo;
    if (r == null) return;
    final next = r.load(childIds: childIds);
    setState(() {
      items = next;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (items == null && repo != null) {
      items = repo!.load(childIds: childIds);
      _pushes ??= PushScope.read(context).messages.listen((_) {
        if (mounted) reload();
      });
    }
  }

  @override
  void dispose() {
    _pushes?.cancel();
    super.dispose();
  }

  Future<void> run(Future<void> Function(MessagesRepository r) action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(repo!);
      reload();
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  /// [empty] shows when there is nothing; without it, [build] gets the empty list.
  Widget list({required List<Widget> Function(List<ChildMessage>) build, String? empty}) {
    if (repo == null) return const _Hint('غير متاح.');
    return RefreshIndicator(
      onRefresh: () async {
        reload();
        await items!.catchError((_) => <ChildMessage>[]);
      },
      child: FutureBuilder<List<ChildMessage>>(
        future: items,
        builder: (context, snap) {
          final children = <Widget>[];
          if (snap.connectionState != ConnectionState.done) {
            children.add(
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          } else if (snap.hasError) {
            final failure = snap.error is SetupError ? (snap.error! as SetupError).failure : SetupFailure.unknown;
            children.add(_Hint(setupFailureMessage(failure)));
          } else if (snap.data!.isEmpty && empty != null) {
            children.add(_Hint(empty));
          } else {
            children.addAll(build(snap.data!));
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          );
        },
      ),
    );
  }
}

/// The parent's الملاحظات tab: what the category supervisor wrote about their children.
class ParentMessagesTab extends StatefulWidget {
  const ParentMessagesTab({super.key});

  @override
  State<ParentMessagesTab> createState() => _ParentMessagesTabState();
}

class _ParentMessagesTabState extends State<ParentMessagesTab> with _MessagesLoader {
  @override
  List<String>? get childIds => null;

  @override
  Widget build(BuildContext context) {
    final me = SessionScope.of(context).profile?.id;
    return list(
      empty: 'لا ملاحظات بعد. حين يكتب مشرف الفئة ملاحظة عن طفلك تظهر هنا ويصلك إشعار.',
      build: (items) => [
        for (final m in items) MessageCard(message: m, me: me, showChild: true, actions: _actions(m, me)),
      ],
    );
  }

  MessageActions _actions(ChildMessage m, String? me) => MessageActions(
    onLike: () => run((r) => m.likedBy.containsKey(me) ? r.unlike(m.id) : r.like(m.id)),
    onReply: (body) => run((r) => r.reply(m.id, body)),
  );
}

/// The supervisor's أولياء الأمور tab: the children of their فئة, to open each one's
/// conversation with the parents.
class SupervisorChannelTab extends StatefulWidget {
  const SupervisorChannelTab({super.key});

  @override
  State<SupervisorChannelTab> createState() => _SupervisorChannelTabState();
}

class _SupervisorChannelTabState extends State<SupervisorChannelTab> with _MessagesLoader {
  String _key = '';

  @override
  List<String>? get childIds => [for (final c in InstructorScope.read(context).data.children) c.id];

  @override
  void didChangeDependencies() {
    final key = [for (final c in InstructorScope.of(context).data.children) c.id].join(',');
    if (key != _key) {
      _key = key;
      items = null;
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) {
        if (data.children.isEmpty) {
          return const _Hint('لا يوجد أطفال في فئتك بعد.');
        }
        return list(
          build: (items) {
            final byChild = <String, List<ChildMessage>>{};
            for (final m in items) {
              byChild.putIfAbsent(m.childId, () => []).add(m);
            }
            return [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'اختر طفلاً لتكتب ملاحظة تصل إلى والديه، ويمكنهما الإعجاب بها أو الرد.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: RaeedColors.grey),
                ),
              ),
              for (final c in data.children)
                Card(
                  child: ListTile(
                    key: Key('channel-child-${c.id}'),
                    leading: InitialAvatar(c.fullName, size: 36),
                    title: Text(c.fullName),
                    subtitle: Text(_summary(byChild[c.id], c)),
                    trailing: _UnreadChevron(childId: c.id),
                    onTap: () async {
                      InboxScope.read(context)?.markMessagesRead(childId: c.id);
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ChildChannelScreen(childId: c.id, childName: c.fullName),
                        ),
                      );
                      if (mounted) reload();
                    },
                  ),
                ),
            ];
          },
        );
      },
    );
  }

  static String _summary(List<ChildMessage>? ms, RosterChild c) {
    if (c.parents.isEmpty) return 'لا ولي أمر مسجّل';
    if (ms == null || ms.isEmpty) return 'لا ملاحظات بعد';
    final replies = ms.fold<int>(0, (n, m) => n + m.replies.length);
    return ['آخر ملاحظة: ${longDay(ms.first.createdAt)}', if (replies > 0) 'ردود: $replies'].join(' · ');
  }
}

/// The count of unread replies and likes about one child, before the chevron.
class _UnreadChevron extends StatelessWidget {
  const _UnreadChevron({required this.childId});

  final String childId;

  @override
  Widget build(BuildContext context) {
    final n = InboxScope.of(context)?.unreadMessages(childId: childId) ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (n > 0)
          Badge(
            key: Key('child-count-$childId'),
            backgroundColor: RaeedColors.error,
            label: Text('$n'),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_left),
      ],
    );
  }
}

/// One child's conversation with their parents, for the supervisor: write a new
/// observation, read likes and replies, answer.
class ChildChannelScreen extends StatefulWidget {
  const ChildChannelScreen({super.key, required this.childId, required this.childName});

  final String childId;
  final String childName;

  @override
  State<ChildChannelScreen> createState() => _ChildChannelScreenState();
}

class _ChildChannelScreenState extends State<ChildChannelScreen> with _MessagesLoader {
  final _body = TextEditingController();
  bool _sending = false;

  @override
  List<String>? get childIds => [widget.childId];

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo!.post(widget.childId, body);
      _body.clear();
      messenger.showSnackBar(const SnackBar(content: Text('أُرسلت الملاحظة إلى الوالدين.')));
      reload();
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = SessionScope.of(context).profile?.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.childName)),
      body: Column(
        children: [
          Expanded(
            child: list(
              empty: 'لا ملاحظات بعد. اكتب أول ملاحظة في الأسفل.',
              build: (items) => [
                for (final m in items)
                  MessageCard(
                    message: m,
                    me: me,
                    actions: MessageActions(
                      onReply: (body) => run((r) => r.reply(m.id, body)),
                      onDelete: m.authorId == me ? () => run((r) => r.delete(m.id)) : null,
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('channel-body'),
                      controller: _body,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'ملاحظة لوالدي ${widget.childName.split(' ').first}',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('channel-send'),
                    tooltip: 'إرسال',
                    onPressed: _body.text.trim().isEmpty || _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageActions {
  const MessageActions({this.onLike, this.onReply, this.onDelete});

  final VoidCallback? onLike;
  final Future<void> Function(String body)? onReply;
  final VoidCallback? onDelete;
}

/// An observation with its likes and replies.
class MessageCard extends StatelessWidget {
  const MessageCard({
    super.key,
    required this.message,
    required this.me,
    required this.actions,
    this.showChild = false,
  });

  final ChildMessage message;
  final String? me;
  final MessageActions actions;
  final bool showChild;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final text = Theme.of(context).textTheme;
    final liked = m.likedBy.containsKey(me);
    final likers = m.likedBy.values.where((n) => n.isNotEmpty).join('، ');
    return Card(
      key: Key('message-${m.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showChild) Text(m.childName, style: text.titleSmall),
                      Text(
                        [if (m.authorName.isNotEmpty) m.authorName, _when(m.createdAt)].join(' · '),
                        style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                      ),
                    ],
                  ),
                ),
                if (actions.onDelete != null)
                  IconButton(
                    tooltip: 'حذف',
                    visualDensity: VisualDensity.compact,
                    onPressed: actions.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(m.body, style: text.bodyLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                if (actions.onLike != null)
                  TextButton.icon(
                    key: Key('like-${m.id}'),
                    onPressed: actions.onLike,
                    icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? RaeedColors.error : null),
                    label: Text(liked ? 'أعجبني' : 'إعجاب'),
                  )
                else if (m.likedBy.isNotEmpty)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 6),
                    child: Icon(Icons.favorite, size: 18, color: RaeedColors.error),
                  ),
                if (likers.isNotEmpty)
                  Expanded(
                    child: Text(
                      actions.onLike != null ? '' : 'أعجب بها: $likers',
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            for (final r in m.replies)
              Container(
                width: double.infinity,
                margin: const EdgeInsetsDirectional.only(start: 12, bottom: 6, end: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: RaeedColors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.authorId == me ? 'أنت' : r.authorName} · ${_when(r.createdAt)}',
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                    ),
                    Text(r.body),
                  ],
                ),
              ),
            if (actions.onReply != null) _ReplyField(messageId: m.id, onReply: actions.onReply!),
          ],
        ),
      ),
    );
  }
}

class _ReplyField extends StatefulWidget {
  const _ReplyField({required this.messageId, required this.onReply});

  final String messageId;
  final Future<void> Function(String body) onReply;

  @override
  State<_ReplyField> createState() => _ReplyFieldState();
}

class _ReplyFieldState extends State<_ReplyField> {
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onReply(body);
    if (!mounted) return;
    _body.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: Key('reply-${widget.messageId}'),
            controller: _body,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'اكتب رداً', isDense: true),
          ),
        ),
        IconButton(
          key: Key('send-reply-${widget.messageId}'),
          tooltip: 'إرسال الرد',
          onPressed: _body.text.trim().isEmpty || _busy ? null : _send,
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: RaeedColors.grey),
    ),
  );
}
