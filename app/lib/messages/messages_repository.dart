import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../setup/setup_repository.dart';

/// A reply under an observation, from a parent or the supervisor.
class MessageReply {
  const MessageReply({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
}

/// An observation the category supervisor wrote about a child for the child's parents.
class ChildMessage {
  const ChildMessage({
    required this.id,
    required this.childId,
    required this.childName,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.replies = const [],
    this.likedBy = const {},
  });

  final String id;
  final String childId;
  final String childName;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  /// Oldest first.
  final List<MessageReply> replies;

  /// Who liked it: id to name.
  final Map<String, String> likedBy;
}

/// The channel between a category supervisor and parents. Every call throws [SetupError].
abstract interface class MessagesRepository {
  /// Newest first: the observations about [childIds], or every one the caller may read.
  Future<List<ChildMessage>> load({List<String>? childIds});
  Future<void> post(String childId, String body);
  Future<void> reply(String messageId, String body);
  Future<void> like(String messageId);
  Future<void> unlike(String messageId);
  Future<void> delete(String messageId);
}

class SupabaseMessagesRepository implements MessagesRepository {
  SupabaseMessagesRepository(this._db);

  final SupabaseClient _db;

  String get _me => _db.auth.currentUser!.id;

  @override
  Future<List<ChildMessage>> load({List<String>? childIds}) => guardSupabase(() async {
    if (childIds != null && childIds.isEmpty) return const [];
    var q = _db
        .from('child_messages')
        .select(
          'id, child_id, author_id, body, created_at, children(full_name), people(full_name), '
          'child_message_replies(id, author_id, body, created_at, people(full_name)), '
          'child_message_likes(person_id, people(full_name))',
        );
    if (childIds != null) q = q.inFilter('child_id', childIds);
    final rows = await q.order('created_at', ascending: false).limit(300);
    String name(Object? p) => (p as Map?)?['full_name'] as String? ?? '';
    return [
      for (final r in rows)
        ChildMessage(
          id: r['id'] as String,
          childId: r['child_id'] as String,
          childName: name(r['children']),
          authorId: r['author_id'] as String,
          authorName: name(r['people']),
          body: r['body'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          replies: [
            for (final x in r['child_message_replies'] as List)
              MessageReply(
                id: x['id'] as String,
                authorId: x['author_id'] as String,
                authorName: name(x['people']),
                body: x['body'] as String,
                createdAt: DateTime.parse(x['created_at'] as String).toLocal(),
              ),
          ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          likedBy: {for (final l in r['child_message_likes'] as List) l['person_id'] as String: name(l['people'])},
        ),
    ];
  });

  @override
  Future<void> post(String childId, String body) =>
      guardSupabase(() => _db.from('child_messages').insert({'child_id': childId, 'author_id': _me, 'body': body}));

  @override
  Future<void> reply(String messageId, String body) => guardSupabase(
    () => _db.from('child_message_replies').insert({'message_id': messageId, 'author_id': _me, 'body': body}),
  );

  @override
  Future<void> like(String messageId) => guardSupabase(
    () => _db.from('child_message_likes').upsert({'message_id': messageId, 'person_id': _me}, ignoreDuplicates: true),
  );

  @override
  Future<void> unlike(String messageId) =>
      guardSupabase(() => _db.from('child_message_likes').delete().eq('message_id', messageId).eq('person_id', _me));

  @override
  Future<void> delete(String messageId) => guardSupabase(() => _db.from('child_messages').delete().eq('id', messageId));
}

/// Hands the messages repository to the screens. Null where the app was started without
/// one (tests that do not cover messages).
class MessagesScope extends InheritedWidget {
  const MessagesScope({super.key, required this.repo, required super.child});

  final MessagesRepository? repo;

  static MessagesRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessagesScope>()?.repo;

  @override
  bool updateShouldNotify(MessagesScope old) => old.repo != repo;
}
