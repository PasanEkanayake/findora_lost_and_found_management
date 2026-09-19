import 'package:flutter/material.dart';

/// One password rule: a human-readable label plus the predicate that
/// decides whether a candidate password satisfies it. Kept as data rather
/// than inlined validator logic so the same rule set can back both the
/// form validator and the live checklist UI without duplicating the
/// conditions in two places that could drift apart.
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String password) test;
}

/// Findora's signup password requirements. Deliberately a bit stricter
/// than the old "6 characters, no other rules" — long enough and varied
/// enough to resist casual guessing, without demanding something
/// unreasonable like a symbol from a specific set.
final List<PasswordRule> passwordRules = [
  PasswordRule('At least 8 characters', (p) => p.length >= 8),
  PasswordRule('One uppercase letter (A–Z)', (p) => p.contains(RegExp(r'[A-Z]'))),
  PasswordRule('One lowercase letter (a–z)', (p) => p.contains(RegExp(r'[a-z]'))),
  PasswordRule('One number (0–9)', (p) => p.contains(RegExp(r'[0-9]'))),
  PasswordRule(
    'One special character (!@#\$…)',
    (p) => p.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]~`/;\\]')),
  ),
];

/// Null (valid) only once every rule in [passwordRules] passes — used as a
/// `TextFormField.validator`, matching how every other field on this form
/// already validates.
String? validateStrongPassword(String? value) {
  final password = value ?? '';
  for (final rule in passwordRules) {
    if (!rule.test(password)) return 'Password needs: ${rule.label.toLowerCase()}';
  }
  return null;
}

/// A compact 0–1 "strength" figure for the meter bar — just the fraction of
/// [passwordRules] currently satisfied, not a separate scoring model. Simple
/// on purpose: the checklist below it already shows exactly what's missing,
/// so the bar only needs to convey "how close is this", not explain itself.
double passwordStrength(String password) {
  if (password.isEmpty) return 0;
  final passed = passwordRules.where((r) => r.test(password)).length;
  return passed / passwordRules.length;
}

/// Live strength bar + checklist, shown under the password field as the
/// person types. Each rule lights up the moment it's satisfied, rather than
/// only reporting pass/fail on submit — this is what actually helps someone
/// construct a valid password instead of trial-and-error against a single
/// error message.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  Color _barColor(BuildContext context, double strength) {
    final theme = Theme.of(context);
    if (strength >= 1.0) return theme.colorScheme.tertiary; // reuses the "found" green
    if (strength >= 0.6) return theme.colorScheme.secondary; // amber
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = passwordStrength(password);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: strength,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: _barColor(context, strength),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final rule in passwordRules)
              _RuleChip(label: rule.label, satisfied: rule.test(password)),
          ],
        ),
      ],
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label, required this.satisfied});

  final String label;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = satisfied ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          satisfied ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
