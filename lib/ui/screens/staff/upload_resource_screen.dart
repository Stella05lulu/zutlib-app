import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../core/theme.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';

/// Mandatory metadata is enforced here and again in the database, so a
/// resource cannot reach the catalogue without the fields retrieval needs.
class UploadResourceScreen extends ConsumerStatefulWidget {
  const UploadResourceScreen({super.key});
  @override
  ConsumerState<UploadResourceScreen> createState() => _UploadResourceScreenState();
}

class _UploadResourceScreenState extends ConsumerState<UploadResourceScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  String? _department;
  int? _semester;
  final _course = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _description = TextEditingController();
  final _url = TextEditingController();
  final _copies = TextEditingController(text: '1');

  ResourceType _type = ResourceType.pastPaper;
  bool _isPhysical = false;
  bool _busy = false;
  PlatformFile? _file;

  @override
  void dispose() {
    for (final c in [_title, _course, _year, _description, _url, _copies]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // PDF only: it opens the same way on every phone and browser.
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _file = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_type == ResourceType.bookLink && _url.text.trim().isEmpty) {
      showMessage(context, 'A recommended book needs a link.', isError: true);
      return;
    }
    if (_type != ResourceType.bookLink && _file == null && !_isPhysical) {
      showMessage(context, 'Attach a file, or mark it as a physical copy.',
          isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await resourceRepo.upload(
        title: _title.text,
        type: _type,
        department: _department!,
        courseCode: _course.text,
        academicYear: int.parse(_year.text.trim()),
        semester: _semester,
        description: _description.text.isEmpty ? null : _description.text,
        fileBytes: _file?.bytes,
        fileName: _file?.name,
        externalUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
        isPhysical: _isPhysical,
        totalCopies: _isPhysical ? (int.tryParse(_copies.text.trim()) ?? 1) : 0,
      );
      ref.invalidate(searchProvider);
      ref.invalidate(staffResourcesProvider);
      ref.invalidate(facetsProvider);
      ref.invalidate(overviewProvider);
      if (!mounted) return;
      showMessage(context, 'Added to the library.');
      context.pop();
    } on Failure catch (f) {
      if (mounted) showMessage(context, f.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a resource')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.md),
        child: Readable(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ResourceType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in ResourceType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Give it a title students will recognise' : null,
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _department,
                        decoration: const InputDecoration(labelText: 'Department'),
                        items: [
                          for (final d in kDepartments)
                            DropdownMenuItem(value: d, child: Text(d)),
                        ],
                        onChanged: (v) => setState(() => _department = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _course,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                            labelText: 'Course code', hintText: 'e.g. EEE 2011'),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Required';
                          if (!RegExp(r'^[A-Za-z]{2,5}[\s._-]*\d{3,4}$')
                              .hasMatch(t)) {
                            return 'Letters then numbers, as on the paper';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _year,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Academic year'),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null || n < 1990 || n > 2100) {
                            return 'Enter a year';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _semester,
                        decoration: const InputDecoration(
                          labelText: 'Semester',
                          helperText: 'Leave blank for tests and deferred exams',
                        ),
                        items: const [
                          DropdownMenuItem<int?>(value: null, child: Text('Not stated')),
                          DropdownMenuItem<int?>(value: 1, child: Text('Semester 1 (June)')),
                          DropdownMenuItem<int?>(value: 2, child: Text('Semester 2 (December)')),
                        ],
                        onChanged: (v) => setState(() => _semester = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    helperText: 'Optional, but it improves search',
                  ),
                ),
                const SizedBox(height: Insets.md),
                if (_type == ResourceType.bookLink)
                  TextFormField(
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'Link to the book',
                      hintText: 'https://',
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: Text(_file?.name ?? 'Attach a document'),
                      subtitle: Text(_file == null
                          ? 'PDF only'
                          : '${((_file!.size) / 1024).round()} KB'),
                      trailing: TextButton(
                        onPressed: _pickFile,
                        child: Text(_file == null ? 'Choose' : 'Change'),
                      ),
                    ),
                  ),
                const SizedBox(height: Insets.md),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _isPhysical,
                        onChanged: (v) => setState(() => _isPhysical = v),
                        title: const Text('The library holds physical copies'),
                        subtitle: const Text(
                            'Students can apply to borrow these'),
                        activeThumbColor: Palette.blue,
                      ),
                      if (_isPhysical) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(Insets.md),
                          child: TextFormField(
                            controller: _copies,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'How many copies'),
                            validator: (v) {
                              if (!_isPhysical) return null;
                              final n = int.tryParse(v?.trim() ?? '');
                              if (n == null || n < 1) return 'At least one';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Insets.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? SizedBox(
                          height: 19, width: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Palette.onAccent))
                      : const Text('Add to the library'),
                ),
                const SizedBox(height: Insets.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
