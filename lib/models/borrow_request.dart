import 'package:flutter/material.dart';
import '../core/theme.dart';

enum BorrowStatus {
  submitted, underReview, approved, rejected,
  collected, returned, overdue, cancelled,
}

extension BorrowStatusX on BorrowStatus {
  String get wire => switch (this) {
        BorrowStatus.submitted => 'submitted',
        BorrowStatus.underReview => 'under_review',
        BorrowStatus.approved => 'approved',
        BorrowStatus.rejected => 'rejected',
        BorrowStatus.collected => 'collected',
        BorrowStatus.returned => 'returned',
        BorrowStatus.overdue => 'overdue',
        BorrowStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        BorrowStatus.submitted => 'Submitted',
        BorrowStatus.underReview => 'Under review',
        BorrowStatus.approved => 'Approved',
        BorrowStatus.rejected => 'Rejected',
        BorrowStatus.collected => 'Collected',
        BorrowStatus.returned => 'Returned',
        BorrowStatus.overdue => 'Overdue',
        BorrowStatus.cancelled => 'Cancelled',
      };

  /// What the student should understand is happening now.
  String get explanation => switch (this) {
        BorrowStatus.submitted => 'Waiting for a librarian to pick it up.',
        BorrowStatus.underReview => 'A librarian is looking at it now.',
        BorrowStatus.approved => 'A copy is reserved for you. Collect it from the library.',
        BorrowStatus.rejected => 'This request was not approved.',
        BorrowStatus.collected => 'You have this item.',
        BorrowStatus.returned => 'Returned. Nothing outstanding.',
        BorrowStatus.overdue => 'This item is past its due date. Please return it.',
        BorrowStatus.cancelled => 'You cancelled this request.',
      };

  Color get fg => switch (this) {
        BorrowStatus.approved || BorrowStatus.returned => Palette.good,
        BorrowStatus.rejected || BorrowStatus.overdue => Palette.bad,
        BorrowStatus.collected => Palette.blueDeep,
        BorrowStatus.cancelled => Palette.inkFaint,
        _ => Palette.warn,
      };

  Color get bg => switch (this) {
        BorrowStatus.approved || BorrowStatus.returned => Palette.goodWash,
        BorrowStatus.rejected || BorrowStatus.overdue => Palette.badWash,
        BorrowStatus.collected => Palette.blueWash,
        BorrowStatus.cancelled => Palette.neutralWash,
        _ => Palette.warnWash,
      };

  bool get isLive => this == BorrowStatus.submitted ||
      this == BorrowStatus.underReview ||
      this == BorrowStatus.approved ||
      this == BorrowStatus.collected ||
      this == BorrowStatus.overdue;

  static BorrowStatus parse(String v) => switch (v) {
        'under_review' => BorrowStatus.underReview,
        'approved' => BorrowStatus.approved,
        'rejected' => BorrowStatus.rejected,
        'collected' => BorrowStatus.collected,
        'returned' => BorrowStatus.returned,
        'overdue' => BorrowStatus.overdue,
        'cancelled' => BorrowStatus.cancelled,
        _ => BorrowStatus.submitted,
      };
}

class BorrowRequest {
  const BorrowRequest({
    required this.id,
    required this.resourceId,
    required this.studentId,
    required this.studentName,
    required this.studentNumber,
    required this.status,
    required this.requestedAt,
    this.programme,
    this.resourceTitle,
    this.courseCode,
    this.collectionDate,
    this.decidedAt,
    this.rejectionReason,
    this.dueDate,
    this.returnedAt,
  });

  final String id;
  final String resourceId;
  final String studentId;
  final String studentName;
  final String studentNumber;
  final String? programme;
  final String? resourceTitle;
  final String? courseCode;
  final BorrowStatus status;
  final DateTime requestedAt;
  final DateTime? collectionDate;
  final DateTime? decidedAt;
  final String? rejectionReason;
  final DateTime? dueDate;
  final DateTime? returnedAt;

  /// Overdue is derived from the due date, so a row that was written as
  /// collected reports itself as overdue once that date has passed.
  BorrowStatus get effectiveStatus {
    if (status == BorrowStatus.collected &&
        dueDate != null &&
        dueDate!.isBefore(DateTime.now())) {
      return BorrowStatus.overdue;
    }
    return status;
  }

  int? get daysUntilDue {
    if (dueDate == null) return null;
    final today = DateTime.now();
    return DateTime(dueDate!.year, dueDate!.month, dueDate!.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  factory BorrowRequest.fromMap(Map<String, dynamic> m) {
    final res = m['resources'];
    return BorrowRequest(
      id: m['id'] as String,
      resourceId: m['resource_id'] as String,
      studentId: m['student_id'] as String,
      studentName: (m['student_name'] ?? '') as String,
      studentNumber: (m['student_number'] ?? '') as String,
      programme: m['programme'] as String?,
      resourceTitle: res is Map ? res['title'] as String? : null,
      courseCode: res is Map ? res['course_code'] as String? : null,
      status: BorrowStatusX.parse(m['status'] as String),
      requestedAt: DateTime.parse(m['requested_at'] as String).toLocal(),
      collectionDate: _date(m['collection_date']),
      decidedAt: _date(m['decided_at']),
      rejectionReason: m['rejection_reason'] as String?,
      dueDate: _date(m['due_date']),
      returnedAt: _date(m['returned_at']),
    );
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
