import 'package:flutter/material.dart';

import '../../../core/theme.dart' show kWideBreakpoint;
import '../../../core/theme/app_theme.dart';

/// Every entry screen (sign in, create account, verify, waiting for
/// approval, choose a password): a flat grey page, the wordmark, and the
/// form on a bordered panel. Uses the flat ZutLib theme from
/// lib/core/theme/app_theme.dart.
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
    return StudyScope(
      child: Builder(builder: (context) {
        final c = StudyColors.of(context);
        final t = Theme.of(context).textTheme;
        final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page, vertical: Gap.wide),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 30,
                            width: 30,
                            decoration: BoxDecoration(
                              color: c.ink,
                              borderRadius: BorderRadius.circular(Radii.control),
                            ),
                            alignment: Alignment.center,
                            child: Text('ZL',
                                style: Mono.of(context, size: 12, weight: FontWeight.w600, color: c.canvas)),
                          ),
                          const SizedBox(width: Gap.snug),
                          Text('ZutLib', style: t.titleMedium),
                        ],
                      ),
                      const SizedBox(height: Gap.section),
                      Container(
                        padding: EdgeInsets.all(wide ? Gap.wide - 8 : Gap.page + 2),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(Radii.panel),
                          border: Border.all(color: c.line),
                        ),
                        // One autofill group per form. On the web, Chrome's
                        // password manager otherwise treats each password box
                        // as its own form and can take focus away from it, so
                        // the box stops accepting typing after you leave it.
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(title, style: t.headlineSmall),
                              const SizedBox(height: Gap.tight),
                              Text(subtitle, style: t.bodyMedium),
                              const SizedBox(height: Gap.page + 4),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.page),
                      Text('Zambia University College of Technology, Ndola', style: t.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
