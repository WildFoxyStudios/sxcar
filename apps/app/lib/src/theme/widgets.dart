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

// ────────────────────────────────────────────────────────────────────────────
// UpsellCard
// Pill-shaped card for upsell blocks. Default style = dark gradient; pass
// `highlighted: true` for the yellow primary CTA style.
// ────────────────────────────────────────────────────────────────────────────

/// Upsell card used in the drawer and Tienda screen.
///
/// - Default: dark linear gradient (kSurface → kChip), radius 16
/// - Highlighted: yellow linear gradient (kYellow → Color(0xFFFFD633))
/// - Optional CTA pill at the bottom (highlighted → black bg + yellow text;
///   default → yellow bg + black text)
class UpsellCard extends StatelessWidget {
  final Widget content;
  final String? ctaLabel;
  final VoidCallback? onTap;
  final bool highlighted;

  const UpsellCard({
    super.key,
    required this.content,
    this.ctaLabel,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: highlighted
            ? const LinearGradient(
                colors: [VibraTheme.kYellow, Color(0xFFFFD633)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF2A2A2A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          if (ctaLabel != null && onTap != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: highlighted ? Colors.black : VibraTheme.kYellow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ctaLabel!,
                  style: TextStyle(
                    color: highlighted ? VibraTheme.kYellow : Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PlanDurationCard
// Duration card used in Tienda screen. Selected = yellow border; popular = grey
// POPULAR tag; savings shown only when provided.
// ────────────────────────────────────────────────────────────────────────────

/// Plan duration card.
///
/// - Shape: rounded 14, padding 12
/// - Unselected: kSurface bg, kDivider border
/// - Selected: kYellow 2 px border, yellow tint overlay (Color(0x33FFCC00))
/// - Optional savings badge "Ahorra N%" (or local equivalent) when [savingsPercent]
///   is non-null
/// - Optional popular badge (grey background, "POPULAR" label) when [popular]
class PlanDurationCard extends StatelessWidget {
  final String duration;
  final String price;
  final String? savingsPercent;
  final bool popular;
  final bool selected;
  final VoidCallback? onTap;

  const PlanDurationCard({
    super.key,
    required this.duration,
    required this.price,
    this.savingsPercent,
    this.popular = false,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x33FFCC00) // kYellow @ ~20% over kSurface
              : VibraTheme.kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? VibraTheme.kYellow : const Color(0xFF333333),
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                if (savingsPercent != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Ahorra $savingsPercent%',
                    style: const TextStyle(
                      color: Color(0xFF8E8E8E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            if (popular)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF666666),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'POPULAR',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// NUEVOBadge
// Small yellow rounded badge with text "NUEVO". Used in PODRÍA INTERESAR
// suggestions and other new-content indicators.
// ────────────────────────────────────────────────────────────────────────────

/// Yellow "NUEVO" badge.
///
/// - Background: kYellow
/// - Text: black, bold, [size] (default 11 sp)
/// - Padding: horizontal 8, vertical 2
/// - Radius: 6
class NUEVOBadge extends StatelessWidget {
  final double size;

  const NUEVOBadge({super.key, this.size = 11});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: VibraTheme.kYellow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'NUEVO',
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: size,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SettingRow
// Row in the settings screen: leading icon + label + subtitle + trailing
// widget (toggle / chevron / segmented3).
// ────────────────────────────────────────────────────────────────────────────

/// One row in the redesigned settings screen.
///
/// Layout (matches visual references 1000144717..1000144724):
///   • Left: optional circle icon (40×40, kChip bg, accent-colored icon)
///   • Middle: title (bold) + subtitle (gray, optional)
///   • Right: trailing widget (toggle, chevron, or segmented)
///
/// Use [onTap] (without `trailing`) for navigation rows; use [trailing] (without
/// `onTap`) for inline-control rows. SettingRow does NOT enforce exclusivity —
/// the caller decides.
class SettingRow extends StatelessWidget {
  /// Optional leading icon (renders as 40×40 circle).
  final IconData? icon;
  final Color? iconColor;

  /// Title (e.g. "Show distance"). Use [AppLocalizations.of(context)!.foo].
  final String title;
  final String? subtitle;

  /// Right-side control. If null + [onTap] provided, shows chevron-right.
  final Widget? trailing;

  /// Tap action. If provided and [trailing] is null, rows show a chevron.
  final VoidCallback? onTap;

  const SettingRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final leading = icon != null
        ? Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: VibraTheme.kChip,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor ?? VibraTheme.kYellow, size: 20),
          )
        : null;

    Widget content = Row(
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: Color(0xFF8E8E8E),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ] else if (onTap != null) ...[
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right,
              color: VibraTheme.kTextSecondary, size: 20),
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: content,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Segmented3
// 3-way segmented control. Used for visitor status (Disabled / Enabled / Auto).
// ────────────────────────────────────────────────────────────────────────────

/// 3-way segmented control.
///
/// - Selected segment: kYellow background, black text
/// - Unselected: transparent, white text
/// - Pill shape (radius 999), full width of parent
class Segmented3 extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const Segmented3({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  }) : assert(options.length == 3, 'Segmented3 requires exactly 3 options');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VibraTheme.kChip,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(3, (i) {
          final selected = i == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? VibraTheme.kYellow : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    options[i],
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
