import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../data/resource_repository.dart';
import '../../../models/resource.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/state_views.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});
  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _bannerClosed = false;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(filtersProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Typing should not fire a query per keystroke.
  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(filtersProvider.notifier).update((f) => f.copyWith(query: value));
    });
  }

  /// Pressing search on the keyboard skips the debounce.
  void _onQuerySubmitted(String value) {
    _debounce?.cancel();
    ref.read(filtersProvider.notifier).update((f) => f.copyWith(query: value));
  }

  void _clearAll() {
    _search.clear();
    ref.read(filtersProvider.notifier).state = const ResourceFilters();
    setState(() {});
  }

  void _open(Resource r) => context.push('/resource/${r.id}');

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(filtersProvider);
    final results = ref.watch(searchProvider);
    final profile = ref.watch(profileProvider).value;
    final width = MediaQuery.sizeOf(context).width;
    // Room for the floating glass nav bar.
    final bottomGap = MediaQuery.paddingOf(context).bottom + Insets.lg;

    return Scaffold(
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(searchProvider);
            ref.invalidate(facetsProvider);
            await ref.read(searchProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Readable(
                    maxWidth: 1100,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Insets.md, Insets.md, Insets.md, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (profile != null) _WelcomeHeader(
                            name: profile.fullName,
                            initials: profile.initials,
                            subtitle: profile.programme ?? profile.department ?? 'ZUT student',
                          ),
                          if (!_bannerClosed) ...[
                            const SizedBox(height: Insets.md),
                            _Banner(onClose: () => setState(() => _bannerClosed = true)),
                          ],
                          const SizedBox(height: Insets.md),
                          _SearchField(
                            controller: _search,
                            onChanged: _onQueryChanged,
                            onSubmitted: _onQuerySubmitted,
                            onClear: () {
                              _search.clear();
                              _onQueryChanged('');
                            },
                          ),
                          const SizedBox(height: Insets.sm),
                          _FilterBar(filters: filters),
                          // Thin bar while a new search runs; the previous
                          // results stay on screen instead of blanking.
                          SizedBox(
                            height: 3,
                            child: results.isLoading && results.hasValue
                                ? const LinearProgressIndicator(minHeight: 3)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ...results.when<List<Widget>>(
                skipLoadingOnReload: true,
                loading: () => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(
                      message: '$e',
                      onRetry: () => ref.invalidate(searchProvider),
                    ),
                  ),
                ],
                data: (items) {
                  if (items.isEmpty) {
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyView(
                          icon: Icons.search_off_rounded,
                          headline: filters.isEmpty
                              ? 'Nothing in the library yet'
                              : 'No resources match that',
                          body: filters.isEmpty
                              ? 'Once a librarian uploads past papers and notes, '
                                  'they will appear here.'
                              : 'Try a different word, or clear a filter.',
                          action: filters.isEmpty
                              ? null
                              : OutlinedButton(
                                  onPressed: _clearAll,
                                  child: const Text('Clear all filters'),
                                ),
                        ),
                      ),
                    ];
                  }
                  // No search and no filters: a Udemy-style home of shelves.
                  if (filters.isEmpty) {
                    return [
                      ..._shelves(items),
                      SliverToBoxAdapter(child: SizedBox(height: bottomGap + 60)),
                    ];
                  }
                  // Searching or filtering: a results grid.
                  return [
                    SliverToBoxAdapter(
                      child: Readable(
                        maxWidth: 1100,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Insets.md, Insets.lg, Insets.md, Insets.sm),
                          child: Text(
                            '${items.length} '
                            '${items.length == 1 ? "result" : "results"}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          Insets.md, Insets.sm, Insets.md, bottomGap + 60),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: catalogGridColumns(width),
                          mainAxisSpacing: Insets.lg,
                          crossAxisSpacing: Insets.md,
                          mainAxisExtent: 250,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ResourceGridCard(
                            resource: items[i],
                            onTap: () => _open(items[i]),
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Recently added" first, then one shelf per resource type that has
  /// anything in it.
  List<Widget> _shelves(List<Resource> items) {
    final shelves = <Widget>[
      _Shelf(
        title: 'Recently added',
        items: items.take(10).toList(),
        onOpen: _open,
      ),
    ];
    const titles = {
      ResourceType.pastPaper: 'Past papers',
      ResourceType.testPaper: 'Test papers',
      ResourceType.lectureNotes: 'Lecture notes',
      ResourceType.bookLink: 'Recommended books',
    };
    for (final type in ResourceType.values) {
      final ofType = items.where((r) => r.type == type).toList();
      if (ofType.isEmpty) continue;
      shelves.add(_Shelf(
        title: titles[type]!,
        items: ofType,
        onOpen: _open,
        onSeeAll: () => ref.read(filtersProvider.notifier)
            .update((f) => f.copyWith(type: type)),
      ));
    }
    return [for (final s in shelves) SliverToBoxAdapter(child: s)];
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.name,
    required this.initials,
    required this.subtitle,
  });
  final String name, initials, subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 54, width: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Palette.accentGradient,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: Palette.blue.withValues(alpha: 0.35),
                blurRadius: 18,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome, $name',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Palette.inkSoft, fontSize: 14.5)),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => context.go('/profile'),
                child: Text('Edit profile and appearance',
                    style: TextStyle(
                      color: Palette.blue,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    )),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Blue gradient strip, in the place of the reference app's promo banner.
class _Banner extends StatelessWidget {
  const _Banner({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Insets.md, 12, 6, 12),
      decoration: BoxDecoration(
        gradient: Palette.accentGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Revise smarter: search any course code to find its past papers.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder pill(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search course code, title or year, e.g. EEE 2011 2024',
        prefixIcon: const Icon(Icons.search_rounded),
        fillColor: Palette.surface.withValues(alpha: Palette.isDark ? 0.7 : 0.85),
        border: pill(Palette.line),
        enabledBorder: pill(Palette.line),
        focusedBorder: pill(Palette.blue, 2),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear search',
                onPressed: onClear,
              ),
      ),
    );
  }
}

/// A heading with a horizontally scrolling row of cards under it.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.items,
    required this.onOpen,
    this.onSeeAll,
  });
  final String title;
  final List<Resource> items;
  final ValueChanged<Resource> onOpen;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.sm, Insets.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
          ),
          SizedBox(
            height: 258,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
              itemBuilder: (_, i) => SizedBox(
                width: 262,
                child: ResourceGridCard(
                  resource: items[i],
                  coverHeight: 140,
                  onTap: () => onOpen(items[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filters});
  final ResourceFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facets = ref.watch(facetsProvider).value;

    void set(ResourceFilters next) =>
        ref.read(filtersProvider.notifier).state = next;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Dropdown<String>(
            hint: 'Department',
            value: filters.department,
            items: facets?.departments ?? const [],
            label: (d) => d,
            onChanged: (v) =>
                set(filters.copyWith(department: v, courseCode: null)),
          ),
          const SizedBox(width: Insets.sm),
          _Dropdown<String>(
            hint: 'Course',
            value: filters.courseCode,
            items: facets?.courseCodes ?? const [],
            label: (c) => c,
            onChanged: (v) => set(filters.copyWith(courseCode: v)),
          ),
          const SizedBox(width: Insets.sm),
          _Dropdown<int>(
            hint: 'Year',
            value: filters.year,
            items: facets?.years ?? const [],
            label: (y) => '$y',
            onChanged: (v) => set(filters.copyWith(year: v)),
          ),
          const SizedBox(width: Insets.sm),
          _Dropdown<ResourceType>(
            hint: 'Type',
            value: filters.type,
            items: ResourceType.values,
            label: (t) => t.label,
            onChanged: (v) => set(filters.copyWith(type: v)),
          ),
          if (filters.activeCount > 0) ...[
            const SizedBox(width: Insets.sm),
            TextButton.icon(
              onPressed: () => set(ResourceFilters(query: filters.query)),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text('Clear ${filters.activeCount}'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? Palette.blueWash : Palette.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? Palette.blue : Palette.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(Corners.field),
          icon: Icon(Icons.expand_more,
              size: 18, color: active ? Palette.blueDeep : Palette.inkFaint),
          hint: Text(hint,
              style: TextStyle(fontSize: 13.5, color: Palette.inkSoft)),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: active ? Palette.blueDeep : Palette.ink,
          ),
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text('Any $hint'.toLowerCase()),
            ),
            for (final item in items)
              DropdownMenuItem<T?>(value: item, child: Text(label(item))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
