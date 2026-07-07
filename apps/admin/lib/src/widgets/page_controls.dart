import 'package:flutter/material.dart';
import '../theme/admin_theme.dart';

/// Reusable pagination controls with Previous / Next buttons.
///
/// [currentPage] is zero-based. [totalPages] is the total number of pages.
/// [onPageChanged] fires with the new zero-based page index.
class PageControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PageControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrevious = currentPage > 0;
    final hasNext = currentPage < totalPages - 1;

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AdminTheme.kSurface,
        border: Border(top: BorderSide(color: AdminTheme.kBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            'Page ${currentPage + 1} of $totalPages',
            style: const TextStyle(color: AdminTheme.kMuted, fontSize: 11),
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: hasPrevious
                    ? AdminTheme.kAccent
                    : AdminTheme.kMuted,
                side: BorderSide(
                  color: hasPrevious
                      ? AdminTheme.kBorder
                      : AdminTheme.kBorder.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              onPressed:
                  hasPrevious ? () => onPageChanged(currentPage - 1) : null,
              child: const Text('Previous'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 26,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    hasNext ? AdminTheme.kAccent : AdminTheme.kMuted,
                side: BorderSide(
                  color: hasNext
                      ? AdminTheme.kBorder
                      : AdminTheme.kBorder.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              onPressed:
                  hasNext ? () => onPageChanged(currentPage + 1) : null,
              child: const Text('Next'),
            ),
          ),
        ],
      ),
    );
  }
}
