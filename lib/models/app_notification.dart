/// A message written to a student by the decide-request function when a
/// librarian acts on their borrowing request.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.subject,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String subject;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        subject: (m['subject'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
      );
}
