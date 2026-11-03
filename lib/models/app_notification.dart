/// A message in the bell: a borrowing decision, a due-date reminder, a new
/// paper for one of the student's courses, an exam reminder, or (for
/// staff) a new request or sign-up. Written only by the database and the
/// server functions; the reader can only mark it read.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.subject,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.kind = 'general',
    this.link,
  });

  final String id;
  final String subject;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// general, borrow, due, upload, study, staff or admin.
  final String kind;

  /// Where tapping it goes, such as /borrowing or /resource/<id>.
  final String? link;

  bool get isUnread => readAt == null;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        subject: (m['subject'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
        kind: (m['kind'] ?? 'general') as String,
        link: m['link'] as String?,
      );
}
