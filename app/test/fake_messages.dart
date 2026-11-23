import 'package:raeed_os/messages/messages_repository.dart';

/// An in-memory stand-in for the supervisor–parents channel.
class FakeMessagesRepository implements MessagesRepository {
  FakeMessagesRepository({required this.me, this.myName = 'أنا'});

  final String me;
  final String myName;
  final messages = <ChildMessage>[];
  final calls = <String>[];
  final childNames = <String, String>{};
  int _ids = 0;

  @override
  Future<List<ChildMessage>> load({List<String>? childIds}) async => [
    for (final m in messages.reversed)
      if (childIds == null || childIds.contains(m.childId)) m,
  ];

  @override
  Future<void> post(String childId, String body) async {
    calls.add('post $childId $body');
    messages.add(
      ChildMessage(
        id: 'm${_ids++}',
        childId: childId,
        childName: childNames[childId] ?? '',
        authorId: me,
        authorName: myName,
        body: body,
        createdAt: DateTime(2027, 2, 10, 12),
      ),
    );
  }

  ChildMessage _with(ChildMessage m, {List<MessageReply>? replies, Map<String, String>? likedBy}) => ChildMessage(
    id: m.id,
    childId: m.childId,
    childName: m.childName,
    authorId: m.authorId,
    authorName: m.authorName,
    body: m.body,
    createdAt: m.createdAt,
    replies: replies ?? m.replies,
    likedBy: likedBy ?? m.likedBy,
  );

  void _update(String id, ChildMessage Function(ChildMessage) f) {
    final i = messages.indexWhere((m) => m.id == id);
    messages[i] = f(messages[i]);
  }

  @override
  Future<void> reply(String messageId, String body) async {
    calls.add('reply $messageId $body');
    _update(
      messageId,
      (m) => _with(
        m,
        replies: [
          ...m.replies,
          MessageReply(
            id: 'r${_ids++}',
            authorId: me,
            authorName: myName,
            body: body,
            createdAt: DateTime(2027, 2, 10, 13),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> like(String messageId) async {
    calls.add('like $messageId');
    _update(messageId, (m) => _with(m, likedBy: {...m.likedBy, me: myName}));
  }

  @override
  Future<void> unlike(String messageId) async {
    calls.add('unlike $messageId');
    _update(messageId, (m) => _with(m, likedBy: {...m.likedBy}..remove(me)));
  }

  @override
  Future<void> delete(String messageId) async {
    calls.add('delete $messageId');
    messages.removeWhere((m) => m.id == messageId);
  }
}
