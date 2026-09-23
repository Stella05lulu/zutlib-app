import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'common.dart';

/// Every screen shows one of four states, so a person is never looking at a
/// blank rectangle wondering whether it is broken or just empty.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? const _Loading(),
        error: (e, _) => ErrorView(message: '$e', onRetry: onRetry),
      );
}

/// Placeholder rows shaped like the list that is about to arrive, so the
/// layout does not jump when it does.
class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Insets.md),
        child: Readable(
          child: Column(
            children: [
              for (var i = 0; i < 4; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: Insets.sm),
                  child: _SkeletonRow(),
                ),
            ],
          ),
        ),
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Corners.card),
          border: Border.all(color: Palette.line),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 220, height: 16),
            SizedBox(height: 10),
            SkeletonBox(width: 140, height: 12),
            SizedBox(height: 10),
            SkeletonBox(height: 12),
          ],
        ),
      );
}

/// A flat grey block standing in for text or an image while loading.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 6});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Palette.neutralWash,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder shaped like a ResourceGridCard.
class SkeletonResourceCard extends StatelessWidget {
  const SkeletonResourceCard({super.key});
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 118, radius: 14),
          SizedBox(height: 12),
          SkeletonBox(height: 15),
          SizedBox(height: 6),
          SkeletonBox(width: 160, height: 15),
          SizedBox(height: 10),
          SkeletonBox(width: 120, height: 11),
        ],
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Palette.bad, size: 30),
                const SizedBox(height: Insets.md),
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                if (onRetry != null) ...[
                  const SizedBox(height: Insets.lg),
                  OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        ),
      );
}

/// An empty screen is an invitation to act, not a dead end.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.headline,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String headline;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56, width: 56,
                  decoration: BoxDecoration(
                      color: Palette.blueWash, shape: BoxShape.circle),
                  child: Icon(icon, color: Palette.blueDeep, size: 26),
                ),
                const SizedBox(height: Insets.md),
                Text(headline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: Insets.sm),
                Text(body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                if (action != null) ...[
                  const SizedBox(height: Insets.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
      );
}
