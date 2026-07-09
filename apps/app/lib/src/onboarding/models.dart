import 'package:flutter/foundation.dart';

enum OnboardingCardKind { required, optional }

@immutable
class OnboardingCard {
  final String id;
  final String label;
  final OnboardingCardKind kind;
  final bool completed;
  final DateTime? skippedAt;
  final String ctaLabel;

  const OnboardingCard({
    required this.id,
    required this.label,
    required this.kind,
    required this.completed,
    required this.skippedAt,
    required this.ctaLabel,
  });

  factory OnboardingCard.fromJson(Map<String, dynamic> json) => OnboardingCard(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        kind: json['kind'] == 'required'
            ? OnboardingCardKind.required
            : OnboardingCardKind.optional,
        completed: json['completed'] as bool? ?? false,
        skippedAt: json['skipped_at'] == null
            ? null
            : DateTime.parse(json['skipped_at'] as String),
        ctaLabel: json['cta_label'] as String? ?? '',
      );
}

@immutable
class OnboardingState {
  final bool onboardingCompleted;
  final DateTime? onboardingCompletedAt;
  final List<OnboardingCard> cards;

  const OnboardingState({
    required this.onboardingCompleted,
    required this.onboardingCompletedAt,
    required this.cards,
  });

  factory OnboardingState.fromJson(Map<String, dynamic> json) =>
      OnboardingState(
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
        onboardingCompletedAt: json['onboarding_completed_at'] == null
            ? null
            : DateTime.parse(json['onboarding_completed_at'] as String),
        cards: (json['cards'] as List? ?? const [])
            .map((c) => OnboardingCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
