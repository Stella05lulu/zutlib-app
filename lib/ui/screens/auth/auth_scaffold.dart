import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../widgets/glass.dart';

/// Every entry screen: white canvas with a soft colour glow, the wordmark,
/// and the form inside a frosted glass card.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    final logo = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 34, width: 34,
          decoration: BoxDecoration(
            gradient: Palette.accentGradient,
            borderRadius: BorderRadius.circular(Corners.field),
          ),
          alignment: Alignment.center,
          child: Text('ZL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              )),
        ),
        const SizedBox(width: Insets.sm),
        Text('ZutLib',
            style: Theme.of(context).textTheme.titleLarge),
      ],
    );

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Insets.sm),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Insets.lg),
        ...children,
      ],
    );

    return Scaffold(
      backgroundColor: Palette.canvas,
      body: GlassBackground(
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg, vertical: Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  logo,
                  const SizedBox(height: Insets.xl),
                  GlassCard(
                    padding: EdgeInsets.all(wide ? Insets.xl : Insets.lg),
                    child: card,
                  ),
                  const SizedBox(height: Insets.lg),
                  Text(
                    'Zambia University College of Technology · Ndola',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
