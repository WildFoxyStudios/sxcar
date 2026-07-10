import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import 'onboarding_provider.dart';
import 'models.dart';
import 'cards/profile_photo_card.dart';
import 'cards/display_name_card.dart';
import 'cards/age_card.dart';
import 'cards/gender_position_card.dart';
import 'cards/looking_for_card.dart';
import 'cards/tribes_card.dart';
import 'cards/vaccines_card.dart';
import 'cards/practices_card.dart';
import 'cards/about_me_card.dart';
import 'cards/height_card.dart';
import 'cards/weight_card.dart';
import 'cards/relationship_status_card.dart';
import 'cards/position_preference_card.dart';
import 'cards/ethnicity_card.dart';

class OnboardingWizardScreen extends StatefulWidget {
  const OnboardingWizardScreen({
    super.key,
    required this.provider,
    this.onCompleted,
  });
  final OnboardingProvider provider;
  final VoidCallback? onCompleted;

  @override
  State<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  late PageController _controller;
  int _index = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    widget.provider.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // The server flips onboarding_completed as soon as the 4 required cards
    // are done (profile_photo, display_name, age, gender_position). Whenever
    // that happens — whether the user tapped "next" or "skip" on the current
    // card — finish the wizard: mark the client state so the router redirect
    // sends us to /navegar. This is the single root path for completion, so
    // skip (which never called onComplete before) now leaves the wizard too.
    if (!_finished && widget.provider.state?.onboardingCompleted == true) {
      _finished = true;
      widget.onCompleted?.call();
      return;
    }
    // A per-card skip removes that optional card from the refreshed list, so
    // the list can shrink under us. If the current index now points past the
    // end (e.g. the last card was skipped), clamp it and move the controller
    // to the new last card so we never render a blank, out-of-bounds page.
    final count = widget.provider.state?.cards.length ?? 0;
    if (count > 0 && _index >= count) {
      _index = count - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_index);
        }
      });
    }
    setState(() {});
  }

  Widget _buildCard(
      OnboardingCard card, OnboardingProvider p, ValueChanged<bool> onComplete) {
    switch (card.id) {
      case 'profile_photo':
        return ProfilePhotoCard(card: card, provider: p, onComplete: onComplete);
      case 'display_name':
        return DisplayNameCard(card: card, provider: p, onComplete: onComplete);
      case 'age':
        return AgeCard(card: card, provider: p, onComplete: onComplete);
      case 'gender_position':
        return GenderPositionCard(card: card, provider: p, onComplete: onComplete);
      case 'looking_for':
        return LookingForCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'tribes':
        return TribesCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'vaccines':
        return VaccinesCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'practices':
        return PracticesCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'about_me':
        return AboutMeCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'height':
        return HeightCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'weight':
        return WeightCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'relationship_status':
        return RelationshipStatusCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'position_preference':
        return PositionPreferenceCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      case 'ethnicity':
        return EthnicityCard(
          card: card, provider: p, onComplete: onComplete,
          onSkip: () => p.skipCards([card.id]),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _confirmSkipAll() async {
    final l10n = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.onboarding_skip_all_confirm_title),
        content: Text(l10n.onboarding_skip_all_confirm_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.onboarding_skip_all_confirm_no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.onboarding_skip_all_confirm_yes),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.provider.forceComplete();
      // Router redirect handles navigation to /navegar via
      // markOnboardingCompleted() — no manual pop needed.
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.provider.state;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cards = state.cards;
    final total = cards.length;
    final requiredDone =
        cards.where((c) => c.kind == OnboardingCardKind.required && c.completed).length;
    final requiredTotal =
        cards.where((c) => c.kind == OnboardingCardKind.required).length;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: VibraTheme.kBg,
          title: Text(l10n.onboarding_title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmSkipAll,
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  '${_index + 1} / $total',
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (_index + 1) / total,
                  minHeight: 6,
                  backgroundColor: VibraTheme.kChip,
                  valueColor: const AlwaysStoppedAnimation(
                      VibraTheme.kBrandPrimary),
                ),
              ),
            ),
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: total,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (ctx, i) {
            if (i >= cards.length) return const SizedBox.shrink();
            final card = cards[i];
            return _buildCard(card, widget.provider, (advanced) {
              if (i + 1 < total) {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              } else {
                // Router redirect handles navigation to /navegar via
                // markOnboardingCompleted() — no manual pop needed.
                widget.onCompleted?.call();
              }
            });
          },
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.onboarding_required_progress(requiredDone, requiredTotal),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
