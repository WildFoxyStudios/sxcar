import 'package:flutter/material.dart';
import 'app_theme.dart';

// ────────────────────────────────────────────────────────────────────────────
// YellowPillButton
// Full-width 56 dp pill, kYellow background, black bold text.
// ────────────────────────────────────────────────────────────────────────────

/// Full-width primary CTA with kYellow background.
///
/// - Height: 56 dp
/// - Shape: rounded-full (radius 28)
/// - Label: 18 sp, w700, black
/// - Disabled: 40 % opacity
class YellowPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  const YellowPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCallback = enabled ? onPressed : null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: ElevatedButton(
          onPressed: effectiveCallback,
          style: ElevatedButton.styleFrom(
            backgroundColor: VibraTheme.kYellow,
            foregroundColor: Colors.black,
            disabledBackgroundColor: VibraTheme.kYellow,
            disabledForegroundColor: Colors.black,
            elevation: 0,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// VibraSegmented
// Pill-shaped segmented control, kChip container, white active tab.
// ────────────────────────────────────────────────────────────────────────────

/// Animated pill-shaped segmented control.
///
/// - Container: kChip, rounded-full
/// - Active option: white pill with black text, w600
/// - Inactive option: transparent with kTextSecondary text
class VibraSegmented extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const VibraSegmented({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: VibraTheme.kChip,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (index) {
          final isSelected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onChanged(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? Colors.black : VibraTheme.kTextSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
                child: Text(options[index]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SectionBand
// Full-width 48 dp section header bar on kBg.
// ────────────────────────────────────────────────────────────────────────────

/// Full-width 48 dp section header band.
///
/// - Background: kBg
/// - Icon: 20 sp, kTextSecondary
/// - Title: 13 sp, UPPERCASE, letter-spacing 1.2, kTextSecondary
class SectionBand extends StatelessWidget {
  final IconData icon;
  final String title;

  const SectionBand({
    super.key,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      color: VibraTheme.kBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: VibraTheme.kTextSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              color: VibraTheme.kTextSecondary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// UnderlineField
// Label + text field with kDivider underline, optional char counter.
// ────────────────────────────────────────────────────────────────────────────

/// Profile-edit style underlined text field.
///
/// - Label: 16 sp, w700, white
/// - Input text: 20 sp, white
/// - Underline: 1 px, kDivider
/// - Counter: shown bottom-right when [maxLength] is provided
/// - Select mode: pass [onTap] + no [controller] for a read-only tappable row
class UnderlineField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;

  /// Static display value; ignored when [controller] is provided.
  final String? value;
  final String? hint;
  final int? maxLength;
  final bool multiline;

  /// When set, the field is read-only and the callback fires on tap.
  final VoidCallback? onTap;

  const UnderlineField({
    super.key,
    required this.label,
    this.controller,
    this.value,
    this.hint,
    this.maxLength,
    this.multiline = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isReadOnly = onTap != null && controller == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: VibraTheme.kTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: isReadOnly ? onTap : null,
          child: TextField(
            controller: controller,
            readOnly: isReadOnly,
            enabled: !isReadOnly,
            maxLength: maxLength,
            maxLines: multiline ? null : 1,
            style: const TextStyle(
              fontSize: 20,
              color: VibraTheme.kTextPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 20,
                color: VibraTheme.kTextTertiary,
              ),
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: VibraTheme.kDivider,
                  width: 1,
                ),
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: VibraTheme.kDivider,
                  width: 1,
                ),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: VibraTheme.kTextPrimary,
                  width: 1,
                ),
              ),
              disabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(
                  color: VibraTheme.kDivider,
                  width: 1,
                ),
              ),
              // Hide the built-in counter; we draw our own below.
              counterText: '',
            ),
          ),
        ),
        if (maxLength != null) ...[
          const SizedBox(height: 4),
          _CounterRow(controller: controller, maxLength: maxLength!),
        ],
      ],
    );
  }
}

class _CounterRow extends StatefulWidget {
  final TextEditingController? controller;
  final int maxLength;

  const _CounterRow({required this.controller, required this.maxLength});

  @override
  State<_CounterRow> createState() => _CounterRowState();
}

class _CounterRowState extends State<_CounterRow> {
  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller?.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller?.text.length ?? 0;
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '$current/${widget.maxLength}',
        style: const TextStyle(
          fontSize: 12,
          color: VibraTheme.kTextSecondary,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// FilterChipPill
// Pill-shaped filter chip: inactive = kChip bg; active = white bg black text.
// ────────────────────────────────────────────────────────────────────────────

/// Horizontal filter chip used in grid/search rows.
///
/// - Inactive: kChip background, white text/icon
/// - Active: white background, black text/icon
class FilterChipPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const FilterChipPill({
    super.key,
    required this.label,
    this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.white : VibraTheme.kChip;
    final fg = active ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AnimatedTheme(
                data: Theme.of(context),
                child: Icon(icon, size: 16, color: fg),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
