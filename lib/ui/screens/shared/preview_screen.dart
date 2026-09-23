import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/admin_repository.dart';
import '../../../models/profile.dart';
import '../../../models/resource.dart';
import '../../widgets/common.dart';
import '../admin/roll_screen.dart';
import '../admin/users_screen.dart';

/// A login-free, backend-free look at the redesigned catalogue grid, for
/// checking the visual work without needing a verified account or live
/// data. Not linked from anywhere in the app's own navigation — reached
/// only by typing the route directly. Safe to delete once it has served
/// its purpose.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  int _tab = 0;

  void _note(BuildContext context) => showMessage(
      context, 'Preview only — this mock card has nothing behind it.');

  @override
  Widget build(BuildContext context) {
    final columns = catalogGridColumns(MediaQuery.sizeOf(context).width);
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: Insets.md,
      crossAxisSpacing: Insets.md,
      mainAxisExtent: 232,
    );

    final tabs = ['Browse', 'Manage resources', 'Student roll', 'Users'];

    return Scaffold(
      appBar: AppBar(title: const Text('Design preview')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Palette.warnWash,
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.md, vertical: 10),
            child: Text(
              'Mock data — nothing here is loaded from Supabase.',
              style: TextStyle(
                color: Palette.warn, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          Container(
            color: Palette.surface,
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                      child: Padding(
                        padding: const EdgeInsets.only(right: Insets.sm),
                        child: ChoiceChip(
                          label: Text(tabs[i]),
                          selected: _tab == i,
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              0 => GridView.builder(
                  padding: const EdgeInsets.all(Insets.md),
                  gridDelegate: gridDelegate,
                  itemCount: _mockResources.length,
                  itemBuilder: (_, i) => ResourceGridCard(
                    resource: _mockResources[i],
                    onTap: () => _note(context),
                  ),
                ),
              1 => GridView.builder(
                  padding: const EdgeInsets.all(Insets.md),
                  gridDelegate: gridDelegate,
                  itemCount: _mockResources.length,
                  itemBuilder: (_, i) => ResourceGridCard(
                    resource: _mockResources[i],
                    onTap: () => _note(context),
                    overlayAction: CardOverlayButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Remove',
                      color: Palette.bad,
                      onPressed: () => _note(context),
                    ),
                  ),
                ),
              2 => GridView.builder(
                  padding: const EdgeInsets.all(Insets.md),
                  gridDelegate: gridDelegate,
                  itemCount: _mockRoll.length,
                  itemBuilder: (_, i) => RollCard(entry: _mockRoll[i]),
                ),
              _ => GridView.builder(
                  padding: const EdgeInsets.all(Insets.md),
                  gridDelegate: gridDelegate,
                  itemCount: _mockUsers.length,
                  itemBuilder: (_, i) => UserCard(
                    profile: _mockUsers[i],
                    onTap: () => _note(context),
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }
}

final _mockResources = [
  const Resource(
    id: 'r1', title: 'Data Structures and Algorithms — Past Paper 2023',
    type: ResourceType.pastPaper, department: 'Computer Science',
    courseCode: 'CS301', academicYear: 2023, isPhysical: true,
    totalCopies: 3, availableCopies: 1,
  ),
  const Resource(
    id: 'r2', title: 'Thermodynamics Test Paper, Semester 1',
    type: ResourceType.testPaper, department: 'Mechanical Engineering',
    courseCode: 'ME210', academicYear: 2024, isPhysical: true,
    totalCopies: 2, availableCopies: 0,
  ),
  const Resource(
    id: 'r3', title: 'Introduction to Databases — Lecture Notes',
    type: ResourceType.lectureNotes, department: 'Computer Science',
    courseCode: 'CS220', academicYear: 2024, isPhysical: false,
    totalCopies: 0, availableCopies: 0,
    externalUrl: 'https://example.com',
  ),
  const Resource(
    id: 'r4', title: 'Clean Code, by Robert C. Martin',
    type: ResourceType.bookLink, department: 'Computer Science',
    courseCode: 'CS100', academicYear: 2022, isPhysical: false,
    totalCopies: 0, availableCopies: 0,
    externalUrl: 'https://example.com',
  ),
  const Resource(
    id: 'r5', title: 'Structural Analysis Past Paper',
    type: ResourceType.pastPaper, department: 'Civil Engineering',
    courseCode: 'CE305', academicYear: 2023, isPhysical: true,
    totalCopies: 4, availableCopies: 4,
  ),
  const Resource(
    id: 'r6', title: 'Organic Chemistry Test Paper',
    type: ResourceType.testPaper, department: 'Applied Chemistry',
    courseCode: 'CH214', academicYear: 2024, isPhysical: true,
    totalCopies: 1, availableCopies: 0,
  ),
];

final _mockRoll = [
  const RollEntry(
    studentNumber: '2300339', firstName: 'Stella', surname: 'Namonje',
    programme: 'BSc Computer Science', department: 'Computer Science',
    intakeYear: 2023, claimed: true,
  ),
  const RollEntry(
    studentNumber: '2300512', firstName: 'John', surname: 'Banda',
    programme: 'BEng Civil Engineering', department: 'Civil Engineering',
    intakeYear: 2023, claimed: false,
  ),
  const RollEntry(
    studentNumber: '2201187', firstName: 'Mary', surname: 'Mwansa',
    programme: 'BSc Applied Chemistry', department: 'Applied Chemistry',
    intakeYear: 2022, claimed: true,
  ),
  const RollEntry(
    studentNumber: '2400021', firstName: null, surname: 'Chileshe',
    programme: 'BEng Mechanical Engineering', department: 'Mechanical Engineering',
    intakeYear: 2024, claimed: false,
  ),
];

final _mockUsers = [
  const Profile(
    id: 'u1', fullName: 'Stella Namonje', surname: 'Namonje',
    role: UserRole.admin, studentNumber: '2300339',
    programme: 'BSc Computer Science',
  ),
  const Profile(
    id: 'u2', fullName: 'Peter Mulenga', surname: 'Mulenga',
    role: UserRole.librarian,
  ),
  const Profile(
    id: 'u3', fullName: 'John Banda', surname: 'Banda',
    role: UserRole.student, studentNumber: '2300512',
    programme: 'BEng Civil Engineering',
  ),
  const Profile(
    id: 'u4', fullName: 'Mary Mwansa', surname: 'Mwansa',
    role: UserRole.student, studentNumber: '2201187',
    programme: 'BSc Applied Chemistry',
  ),
];
