import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../../study/recommend.dart' show normaliseCourse;

/// Choose up to 12 courses: type a code (the library's codes are
/// suggested as you type) and press Add; tap a chip's cross to remove it.
class CoursePicker extends ConsumerStatefulWidget {
  const CoursePicker({super.key, required this.courses, required this.onChanged});
  final List<String> courses;
  final ValueChanged<List<String>> onChanged;

  static const max = 12;

  @override
  ConsumerState<CoursePicker> createState() => _CoursePickerState();
}

class _CoursePickerState extends ConsumerState<CoursePicker> {
  TextEditingController? _field;
  String? _error;

  void _add(String raw) {
    final code = normaliseCourse(raw);
    if (code.isEmpty) return;
    if (!RegExp(r'^[A-Z0-9 ]{2,20}$').hasMatch(code)) {
      setState(() => _error = 'Use letters, digits and spaces, like EEE 2011.');
      return;
    }
    if (widget.courses.contains(code)) {
      _field?.clear();
      return;
    }
    if (widget.courses.length >= CoursePicker.max) {
      setState(() => _error = 'You can choose up to ${CoursePicker.max} courses.');
      return;
    }
    setState(() => _error = null);
    widget.onChanged([...widget.courses, code]);
    _field?.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyColors.of(context);
    final t = Theme.of(context).textTheme;
    final known = ref.watch(facetsProvider).valueOrNull?.courseCodes ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (value) {
                  final q = normaliseCourse(value.text);
                  if (q.isEmpty) return const Iterable<String>.empty();
                  return known
                      .map(normaliseCourse)
                      .where((k) => k.contains(q) && !widget.courses.contains(k))
                      .toSet()
                      .take(8);
                },
                onSelected: _add,
                fieldViewBuilder: (context, controller, focus, onSubmit) {
                  _field = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'Course code, e.g. EEE 2011',
                      errorText: _error,
                    ),
                    onSubmitted: _add,
                  );
                },
              ),
            ),
            const SizedBox(width: Gap.tight),
            OutlinedButton(onPressed: () => _add(_field?.text ?? ''), child: const Text('Add')),
          ],
        ),
        const SizedBox(height: Gap.snug),
        if (widget.courses.isEmpty)
          Text('No courses yet. They decide which new papers you hear about and what Explore suggests.',
              style: t.bodySmall)
        else
          Wrap(
            spacing: Gap.tight,
            runSpacing: Gap.tight,
            children: [
              for (final code in widget.courses)
                InputChip(
                  label: Text(code, style: Mono.of(context, size: 13, color: c.ink)),
                  onDeleted: () => widget.onChanged([...widget.courses]..remove(code)),
                  deleteButtonTooltipMessage: 'Remove $code',
                ),
            ],
          ),
      ],
    );
  }
}
