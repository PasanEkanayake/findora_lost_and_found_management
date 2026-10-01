import 'package:flutter/material.dart';

/// Read-only row of five stars for [rating] (0–5). Fractions round to the
/// nearest half star, which is how averages like 4.6 are usually shown.
///
/// Announced to screen readers as one phrase ("4 out of 5 stars") instead of
/// five separate icons.
class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.size = 18, this.color});

  final double rating;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Theme.of(context).colorScheme.secondary;
    final rounded = (rating * 2).round() / 2;
    final label = rounded == rounded.roundToDouble()
        ? '${rounded.toInt()} out of 5 stars'
        : '$rounded out of 5 stars';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              rounded >= i
                  ? Icons.star_rounded
                  : (rounded >= i - 0.5 ? Icons.star_half_rounded : Icons.star_border_rounded),
              size: size,
              color: starColor,
            ),
        ],
      ),
    );
  }
}
