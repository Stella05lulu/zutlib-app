// Unit tests for the logic that runs on the phone rather than in the
// database: parsing rows, derived states and the CSV reader.
//
//   flutter test
import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/core/csv.dart';
import 'package:zutlib/data/resource_repository.dart';
import 'package:zutlib/models/borrow_request.dart';
import 'package:zutlib/models/profile.dart';
import 'package:zutlib/models/resource.dart';

Map<String, dynamic> _request({
  String status = 'collected',
  String? dueDate,
}) =>
    {
      'id': 'r1',
      'resource_id': 'x1',
      'student_id': 's1',
      'student_name': 'Ann Alpha',
      'student_number': '2300339',
      'status': status,
      'requested_at': '2026-09-01T10:00:00Z',
      'due_date': dueDate,
      'resources': {'title': 'Electric Circuits', 'course_code': 'EEE 2021'},
    };

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('Resource types', () {
    test('every type survives a round trip to the database value', () {
      for (final t in ResourceType.values) {
        expect(ResourceTypeX.parse(t.wire), t);
      }
    });

    test('an unknown database value falls back to past paper', () {
      expect(ResourceTypeX.parse('something_new'), ResourceType.pastPaper);
    });

    test('departments are the three ZUT schools', () {
      expect(kDepartments, ['Business', 'Engineering', 'ICT']);
    });
  });

  group('Resource availability', () {
    Resource make({bool physical = true, int total = 3, int available = 1}) =>
        Resource.fromMap({
          'id': 'a',
          'title': 'Analogue Electronics',
          'type': 'past_paper',
          'department': 'Engineering',
          'course_code': 'EEE 2040',
          'academic_year': 2025,
          'is_physical': physical,
          'total_copies': total,
          'available_copies': available,
          'file_path': 'engineering/EEE2040/x.pdf',
        });

    test('digital only', () {
      final r = make(physical: false, total: 0, available: 0);
      expect(r.availabilityLabel, 'Digital only');
      expect(r.canBeBorrowed, isFalse);
      expect(r.hasDigitalCopy, isTrue);
    });

    test('copies on the shelf can be borrowed', () {
      final r = make();
      expect(r.availabilityLabel, '1 of 3 available');
      expect(r.canBeBorrowed, isTrue);
    });

    test('all copies out cannot be borrowed', () {
      final r = make(available: 0);
      expect(r.availabilityLabel, 'All 3 copies on loan');
      expect(r.canBeBorrowed, isFalse);
    });
  });

  group('Borrowing status', () {
    test('every status survives a round trip to the database value', () {
      for (final s in BorrowStatus.values) {
        expect(BorrowStatusX.parse(s.wire), s);
      }
    });

    test('a collected item past its due date reports itself overdue', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final r = BorrowRequest.fromMap(_request(dueDate: _day(past)));
      expect(r.status, BorrowStatus.collected);
      expect(r.effectiveStatus, BorrowStatus.overdue);
      expect(r.daysUntilDue, -3);
    });

    test('a collected item not yet due stays collected', () {
      final future = DateTime.now().add(const Duration(days: 5));
      final r = BorrowRequest.fromMap(_request(dueDate: _day(future)));
      expect(r.effectiveStatus, BorrowStatus.collected);
      expect(r.daysUntilDue, 5);
    });

    test('live and closed states', () {
      expect(BorrowStatus.submitted.isLive, isTrue);
      expect(BorrowStatus.approved.isLive, isTrue);
      expect(BorrowStatus.overdue.isLive, isTrue);
      expect(BorrowStatus.returned.isLive, isFalse);
      expect(BorrowStatus.rejected.isLive, isFalse);
      expect(BorrowStatus.cancelled.isLive, isFalse);
    });

    test('the joined resource title and course code are read', () {
      final r = BorrowRequest.fromMap(_request(status: 'submitted'));
      expect(r.resourceTitle, 'Electric Circuits');
      expect(r.courseCode, 'EEE 2021');
    });
  });

  group('Profiles', () {
    Profile make(String name, String role) => Profile.fromMap(
        {'id': 'p', 'full_name': name, 'surname': 'x', 'role': role});

    test('initials use first and last name', () {
      expect(make('Stella Lukundo Namonje', 'student').initials, 'SN');
      expect(make('stella', 'student').initials, 'S');
    });

    test('roles parse, and anything unknown is treated as a student', () {
      expect(make('a', 'librarian').role, UserRole.librarian);
      expect(make('a', 'admin').role.isStaff, isTrue);
      expect(make('a', 'superuser').role, UserRole.student);
    });
  });

  group('Search filters', () {
    test('changing department can clear the course', () {
      const f = ResourceFilters(department: 'ICT', courseCode: 'ICT 1131');
      final next = f.copyWith(department: 'Engineering', courseCode: null);
      expect(next.department, 'Engineering');
      expect(next.courseCode, isNull);
    });

    test('copyWith keeps fields that are not mentioned', () {
      const f = ResourceFilters(query: 'eee', year: 2024);
      final next = f.copyWith(query: 'ete');
      expect(next.year, 2024);
      expect(next.activeCount, 1);
      expect(const ResourceFilters().isEmpty, isTrue);
    });
  });

  group('CSV reader (roll import)', () {
    test('quoted commas, doubled quotes and CRLF endings', () {
      final rows = parseCsv(
          'student_number,surname,programme\r\n'
          '2300339,"O\'Neil, Jr",Bachelor of IT\r\n'
          '2300340,"Say ""hi""",BIT\r\n');
      expect(rows.length, 3);
      expect(rows[1][1], "O'Neil, Jr");
      expect(rows[2][1], 'Say "hi"');
    });

    test('Excel byte-order mark and blank lines are ignored', () {
      final rows = parseCsv('﻿student_number,surname\n\n2300339,Banda\n');
      expect(rows.first.first, 'student_number');
      expect(rows.length, 2);
    });
  });
}
