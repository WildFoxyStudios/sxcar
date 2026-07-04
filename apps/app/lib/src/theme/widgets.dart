import 'package:flutter/material.dart';
import 'package:app/src/albums/shared_albums_provider.dart';
import 'package:app/l10n/gen/app_localizations.dart';
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
// Small yellow rounded badge with the localized "NUEVO" label, indicating
// that a user account is < 7 days old (or, in the .small variant, that the
// tile they're shown on is for a recent account).
//
// Two presets:
//   • NUEVOBadge()      — full size, used on profile detail hero + suggestion
//                          row (default fontSize 10, radius 12, padding 8×2)
//   • NUEVOBadge.small() — compact size, used inside Cascade + Explore tiles
//                          (fontSize 9, radius 10, padding 6×2)
//
// Localized via AppLocalizations.badgeNew (es="NUEVO", en="NEW"). The Spanish
// ARB value matches the legacy hardcoded text — that is why the existing
// _wrap(test)->expect find.text('NUEVO') tests still pass.
// ────────────────────────────────────────────────────────────────────────────

class NUEVOBadge extends StatelessWidget {
  final double size;
  final double radius;
  final EdgeInsetsGeometry padding;

  const NUEVOBadge({
    super.key,
    this.size = 10,
    this.radius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  });

  /// Compact tile preset: smaller font + radius, tighter padding (6×2).
  const NUEVOBadge.small({super.key})
      : size = 9,
        radius = 10,
        padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: VibraTheme.kYellow,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        l.badgeNew,
        style: TextStyle(
          color: VibraTheme.kBg,
          fontSize: size,
          fontWeight: FontWeight.w700,
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

// ────────────────────────────────────────────────────────────────────────────
// AlbumCarousel
//
// Horizontal scrollable carousel of album thumbnails for the chat list screen.
// Renders above the conversation list when the user has at least one shared
// album with new photos. Tapping a tile calls [onTap] (e.g. navigate to album
// detail).
// ────────────────────────────────────────────────────────────────────────────

class AlbumCarousel extends StatelessWidget {
  /// List of shared albums to display.
  final List<SharedAlbum> albums;

  /// Tap handler for an album tile (receives the album id).
  final ValueChanged<String> onTap;

  /// Optional height override; default 96 dp.
  final double height;

  const AlbumCarousel({
    super.key,
    required this.albums,
    required this.onTap,
    this.height = 96,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: VibraTheme.kBg,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final album = albums[i];
          return GestureDetector(
            onTap: () => onTap(album.id),
            child: Container(
              width: 96,
              decoration: BoxDecoration(
                color: VibraTheme.kSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: album.coverPhotoUrl != null
                        ? Image.network(
                            album.coverPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _AlbumPlaceholder(),
                          )
                        : const _AlbumPlaceholder(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Text(
                      album.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: VibraTheme.kChip,
      child: const Icon(Icons.photo_album_outlined,
          color: VibraTheme.kTextSecondary, size: 28),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AlbumUpdateBanner
//
// Yellow inline banner shown on the chat list when a recipient has new photos
// in one or more shared albums. Single-row tap → calls [onTap] (open the
// carousel / first album detail).
// ────────────────────────────────────────────────────────────────────────────

class AlbumUpdateBanner extends StatelessWidget {
  /// Number of albums with new photos.
  final int count;

  /// Tap handler.
  final VoidCallback onTap;

  const AlbumUpdateBanner({
    super.key,
    required this.count,
    required this.onTap,
  }) : assert(count >= 0, 'count must be non-negative');

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Material(
      color: VibraTheme.kYellow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.black, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label(context, count),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                AppLocalizations.of(context)?.ver ?? 'Ver',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.black, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _label(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context)!;
    if (count == 1) {
      return l10n.albumActualizadoSingular;
    }
    return l10n.albumesActualizadosPlural(count);
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AlbumUpdatesEmptyState
//
// Centered empty state shown when the user has no shared album updates.
// Mirrors the visual style of BlocksListScreen's empty state.
// ────────────────────────────────────────────────────────────────────────────

class AlbumUpdatesEmptyState extends StatelessWidget {
  const AlbumUpdatesEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: VibraTheme.kSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.collections_outlined,
                color: VibraTheme.kTextSecondary,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)?.noHayActualizaciones ??
                  'No hay actualizaciones de álbum',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// ChipMultiSelect
// Horizontally-scrollable wrap of selectable pills for multi-value sets.
// ────────────────────────────────────────────────────────────────────────────

/// Multi-select chip row. Used by edit-profile selector sheets (tribes,
/// looking_for, meet_at, tags, vaccines, practices) and section pickers.
///
/// Tokens: kSurface unselected, kYellow.withValues(alpha: 0.2) selected,
/// kTextSecondary unselected label, kTextPrimary selected label.
///
/// Wraps to next line if horizontal scroll disabled. Default max visible
/// per row = 8 before wrap (VibraTheme.kPadPage × 4.5 ≈ compact 4-col grid).
///
/// Tapping a chip toggles its membership in [selected]. If [maxSelections]
/// is non-null and reached, non-selected chips render as disabled.
class ChipMultiSelect extends StatelessWidget {
  /// All available options. Each item is the label shown in the chip.
  final List<String> options;

  /// Currently selected option labels (immutable from caller side).
  final Set<String> selected;

  /// Fires with the **new** selected set after a tap toggles membership.
  final ValueChanged<Set<String>> onChanged;

  /// Optional cap; null = unlimited.
  final int? maxSelections;

  /// When true, choices are horizontally scrollable on a single row;
  /// when false (default), they wrap to multiple rows.
  final bool scrollHorizontal;

  const ChipMultiSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.maxSelections,
    this.scrollHorizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final atMax = maxSelections != null && selected.length >= maxSelections!;
    final chips = options.map((label) {
      final isSel = selected.contains(label);
      final isDisabled = !isSel && atMax;
      return _Chip(
        label: label,
        selected: isSel,
        disabled: isDisabled,
        onTap: isDisabled
            ? null
            : () {
                final next = Set<String>.from(selected);
                if (isSel) {
                  next.remove(label);
                } else {
                  next.add(label);
                }
                onChanged(next);
              },
      );
    }).toList();

    if (scrollHorizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: VibraTheme.kPadPage),
        child: Row(children: chips),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VibraTheme.kPadPage),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? VibraTheme.kYellow.withValues(alpha: 0.2)
        : VibraTheme.kSurface;
    final fg = disabled
        ? VibraTheme.kTextTertiary
        : selected
            ? VibraTheme.kTextPrimary
            : VibraTheme.kTextSecondary;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(VibraTheme.kRadiusChip),
        child: InkWell(
          borderRadius: BorderRadius.circular(VibraTheme.kRadiusChip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
