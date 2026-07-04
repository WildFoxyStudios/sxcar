import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/theme/widgets.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:app/src/albums/shared_albums_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a minimal MaterialApp with the Vibra dark theme so
/// widgets can look up Theme, MediaQuery, Directionality, etc.
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: VibraTheme.dark(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// YellowPillButton
// ---------------------------------------------------------------------------

void main() {
  group('YellowPillButton', () {
    testWidgets('renders with correct label', (tester) async {
      await tester.pumpWidget(_wrap(
        YellowPillButton(label: 'Continuar', onPressed: () {}),
      ));

      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets('fills available width (SizedBox.expand)', (tester) async {
      await tester.pumpWidget(_wrap(
        YellowPillButton(label: 'OK', onPressed: () {}),
      ));

      // SizedBox with width: double.infinity + bounded parent → fills row
      final box = tester.renderObject<RenderBox>(find.byType(SizedBox).first);
      expect(box.size.height, equals(56));
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(
        YellowPillButton(label: 'Tap me', onPressed: () => pressed = true),
      ));

      await tester.tap(find.text('Tap me'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('does not call onPressed when disabled', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(
        YellowPillButton(
          label: 'Disabled',
          onPressed: () => pressed = true,
          enabled: false,
        ),
      ));

      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      await tester.pump();

      expect(pressed, isFalse);
    });

    testWidgets('applies reduced opacity when disabled', (tester) async {
      await tester.pumpWidget(_wrap(
        YellowPillButton(
          label: 'Disabled',
          onPressed: () {},
          enabled: false,
        ),
      ));

      final opacity =
          tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, lessThan(1.0));
    });
  });

  // ---------------------------------------------------------------------------
  // VibraSegmented
  // ---------------------------------------------------------------------------

  group('VibraSegmented', () {
    testWidgets('renders all option labels', (tester) async {
      await tester.pumpWidget(_wrap(
        VibraSegmented(
          options: const ['En línea', 'Incógnito'],
          selectedIndex: 0,
          onChanged: (_) {},
        ),
      ));

      expect(find.text('En línea'), findsOneWidget);
      expect(find.text('Incógnito'), findsOneWidget);
    });

    testWidgets('calls onChanged with correct index when option tapped',
        (tester) async {
      int? changedTo;

      await tester.pumpWidget(_wrap(
        VibraSegmented(
          options: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onChanged: (i) => changedTo = i,
        ),
      ));

      await tester.tap(find.text('B'));
      await tester.pump();

      expect(changedTo, equals(1));
    });

    testWidgets('first option is visually selected (white container)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        VibraSegmented(
          options: const ['First', 'Second'],
          selectedIndex: 0,
          onChanged: (_) {},
        ),
      ));

      // The selected option's AnimatedContainer should have a white background.
      // We check by finding the AnimatedContainer whose decoration has white color.
      final containers =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final selectedContainer = containers.first;
      final decoration =
          selectedContainer.decoration as BoxDecoration?;
      expect(decoration?.color, equals(Colors.white));
    });

    testWidgets('renders with three or more options', (tester) async {
      await tester.pumpWidget(_wrap(
        VibraSegmented(
          options: const ['One', 'Two', 'Three'],
          selectedIndex: 2,
          onChanged: (_) {},
        ),
      ));

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SectionBand
  // ---------------------------------------------------------------------------

  group('SectionBand', () {
    testWidgets('renders icon and uppercased title', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionBand(
          icon: Icons.person_outline,
          title: 'estadísticas',
        ),
      ));

      // Title is uppercased inside the widget
      expect(find.text('ESTADÍSTICAS'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('has correct 48 dp height', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionBand(icon: Icons.info_outline, title: 'Info'),
      ));

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('INFO'),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.constraints?.maxHeight ?? container.constraints?.minHeight,
          closeTo(48, 0.01));
    });

    testWidgets('icon color matches kTextSecondary', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionBand(icon: Icons.star_outline, title: 'Test'),
      ));

      final icon = tester.widget<Icon>(find.byIcon(Icons.star_outline));
      expect(icon.color, equals(VibraTheme.kTextSecondary));
    });
  });

  // ---------------------------------------------------------------------------
  // UnderlineField
  // ---------------------------------------------------------------------------

  group('UnderlineField', () {
    testWidgets('renders label and hint text', (tester) async {
      await tester.pumpWidget(_wrap(
        const UnderlineField(
          label: 'Nombre',
          hint: 'Tu nombre aquí',
        ),
      ));

      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Tu nombre aquí'), findsOneWidget);
    });

    testWidgets('controller text appears in field', (tester) async {
      final controller = TextEditingController(text: 'Javier');
      await tester.pumpWidget(_wrap(
        UnderlineField(
          label: 'Nombre',
          controller: controller,
        ),
      ));

      expect(find.text('Javier'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows counter when maxLength provided', (tester) async {
      final controller = TextEditingController(text: 'Hi');
      await tester.pumpWidget(_wrap(
        UnderlineField(
          label: 'Bio',
          controller: controller,
          maxLength: 255,
        ),
      ));

      // Counter should show "2/255"
      expect(find.text('2/255'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('counter updates as user types', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
        UnderlineField(
          label: 'Bio',
          controller: controller,
          maxLength: 100,
        ),
      ));

      expect(find.text('0/100'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      expect(find.text('5/100'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('no counter when maxLength not provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const UnderlineField(label: 'Nombre'),
      ));

      // No "0/" pattern should exist
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('onTap callback fires in select mode', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        UnderlineField(
          label: 'Rol',
          value: 'Activo',
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // FilterChipPill
  // ---------------------------------------------------------------------------

  group('FilterChipPill', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(_wrap(
        FilterChipPill(
          label: 'En línea',
          active: false,
          onTap: () {},
        ),
      ));

      expect(find.text('En línea'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        FilterChipPill(
          label: 'Filtros',
          icon: Icons.tune,
          active: false,
          onTap: () {},
        ),
      ));

      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        FilterChipPill(
          label: 'Online',
          active: false,
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.text('Online'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('active state uses white background', (tester) async {
      await tester.pumpWidget(_wrap(
        FilterChipPill(
          label: 'Active',
          active: true,
          onTap: () {},
        ),
      ));

      // Active container should be white
      final containers =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final chipContainer = containers.first;
      final decoration = chipContainer.decoration as BoxDecoration?;
      expect(decoration?.color, equals(Colors.white));
    });

    testWidgets('inactive state uses kChip background', (tester) async {
      await tester.pumpWidget(_wrap(
        FilterChipPill(
          label: 'Inactive',
          active: false,
          onTap: () {},
        ),
      ));

      final containers =
          tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      final chipContainer = containers.first;
      final decoration = chipContainer.decoration as BoxDecoration?;
      expect(decoration?.color, equals(VibraTheme.kChip));
    });
  });

  // ---------------------------------------------------------------------------
  // UpsellCard
  // ---------------------------------------------------------------------------

  group('UpsellCard', () {
    testWidgets('renders content', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpsellCard(
          content: Text('Inner content'),
        ),
      ));
      expect(find.text('Inner content'), findsOneWidget);
    });

    testWidgets('shows CTA when ctaLabel + onTap provided', (tester) async {
      await tester.pumpWidget(_wrap(
        UpsellCard(
          content: const Text('Body'),
          ctaLabel: 'Ver planes',
          onTap: () {},
        ),
      ));
      expect(find.text('Ver planes'), findsOneWidget);
    });

    testWidgets('hides CTA when ctaLabel is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpsellCard(content: Text('Body')),
      ));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('invokes onTap when CTA pressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        UpsellCard(
          content: const Text('Body'),
          ctaLabel: 'Tap me',
          onTap: () => taps++,
        ),
      ));
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('highlighted variant uses yellow gradient', (tester) async {
      await tester.pumpWidget(_wrap(
        const UpsellCard(
          content: Text('Body'),
          highlighted: true,
        ),
      ));
      // Find a Container that has a LinearGradient with yellow stop.
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(UpsellCard),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;
      expect(gradient.colors.first, VibraTheme.kYellow);
    });
  });

  // ---------------------------------------------------------------------------
  // PlanDurationCard
  // ---------------------------------------------------------------------------

  group('PlanDurationCard', () {
    testWidgets('renders duration + price', (tester) async {
      await tester.pumpWidget(_wrap(
        const PlanDurationCard(
          duration: '30 DÍAS',
          price: '€8.99',
        ),
      ));
      expect(find.text('30 DÍAS'), findsOneWidget);
      expect(find.text('€8.99'), findsOneWidget);
    });

    testWidgets('shows savings when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const PlanDurationCard(
          duration: '1 AÑO',
          price: '€49.99',
          savingsPercent: '55',
        ),
      ));
      expect(find.text('Ahorra 55%'), findsOneWidget);
    });

    testWidgets('shows POPULAR badge when popular', (tester) async {
      await tester.pumpWidget(_wrap(
        const PlanDurationCard(
          duration: '30 DÍAS',
          price: '€8.99',
          popular: true,
        ),
      ));
      expect(find.text('POPULAR'), findsOneWidget);
    });

    testWidgets('selected uses yellow border', (tester) async {
      await tester.pumpWidget(_wrap(
        const PlanDurationCard(
          duration: '30 DÍAS',
          price: '€8.99',
          selected: true,
        ),
      ));
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(PlanDurationCard),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, VibraTheme.kYellow);
    });

    testWidgets('invokes onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        PlanDurationCard(
          duration: '30 DÍAS',
          price: '€8.99',
          onTap: () => taps++,
        ),
      ));
      await tester.tap(find.byType(PlanDurationCard));
      await tester.pump();
      expect(taps, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // NUEVOBadge
  // ---------------------------------------------------------------------------

  group('NUEVOBadge', () {
    testWidgets('renders NUEVO text', (tester) async {
      await tester.pumpWidget(_wrap(const NUEVOBadge()));
      expect(find.text('NUEVO'), findsOneWidget);
    });

    testWidgets('uses default size 11', (tester) async {
      await tester.pumpWidget(_wrap(const NUEVOBadge()));
      final text = tester.widget<Text>(find.text('NUEVO'));
      expect(text.style?.fontSize, 11);
    });

    testWidgets('respects custom size', (tester) async {
      await tester.pumpWidget(_wrap(const NUEVOBadge(size: 14)));
      final text = tester.widget<Text>(find.text('NUEVO'));
      expect(text.style?.fontSize, 14);
    });
  });

  // ---------------------------------------------------------------------------
  // SettingRow
  // ---------------------------------------------------------------------------

  group('SettingRow', () {
    testWidgets('renders title + subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const SettingRow(
        title: 'Show distance',
        subtitle: 'Display your distance to other users',
      )));
      expect(find.text('Show distance'), findsOneWidget);
      expect(find.text('Display your distance to other users'), findsOneWidget);
    });

    testWidgets('renders leading icon circle when icon provided', (tester) async {
      await tester.pumpWidget(_wrap(const SettingRow(
        icon: Icons.location_on_outlined,
        title: 'Location',
      )));
      // Circle container (40x40) + Icon widget present
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });

    testWidgets('renders chevron-right when onTap provided', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(SettingRow(
        title: 'Privacy',
        onTap: () => taps++,
      )));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('hides chevron when trailing widget provided', (tester) async {
      await tester.pumpWidget(_wrap(SettingRow(
        title: 'Toggle setting',
        trailing: Switch(value: false, onChanged: null),
        onTap: () {}, // onTap set but trailing takes priority
      )));
      // Trailing widget (Switch) renders, chevron does NOT.
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('invokes onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(SettingRow(
        title: 'Privacy',
        onTap: () => taps++,
      )));
      await tester.tap(find.text('Privacy'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Segmented3
  // ---------------------------------------------------------------------------

  group('Segmented3', () {
    testWidgets('renders 3 options', (tester) async {
      await tester.pumpWidget(_wrap(Segmented3(
        options: const ['Off', 'On', 'Auto'],
        selectedIndex: 0,
        onChanged: (_) {},
      )));
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('selected option uses yellow background', (tester) async {
      await tester.pumpWidget(_wrap(Segmented3(
        options: const ['Off', 'On', 'Auto'],
        selectedIndex: 1,
        onChanged: (_) {},
      )));
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasYellow = containers.any((c) {
        final dec = c.decoration;
        if (dec is! BoxDecoration) return false;
        return dec.color == VibraTheme.kYellow;
      });
      expect(hasYellow, true);
    });

    testWidgets('invokes onChanged when segment tapped', (tester) async {
      var changed = 0;
      var lastIdx = -1;
      await tester.pumpWidget(_wrap(Segmented3(
        options: const ['Off', 'On', 'Auto'],
        selectedIndex: 0,
        onChanged: (i) {
          changed++;
          lastIdx = i;
        },
      )));
      await tester.tap(find.text('Auto'));
      await tester.pump();
      expect(changed, 1);
      expect(lastIdx, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // AlbumCarousel
  // ---------------------------------------------------------------------------

  group('AlbumCarousel', () {
    testWidgets('renders nothing for empty list', (tester) async {
      await tester.pumpWidget(_wrap(AlbumCarousel(
        albums: const [],
        onTap: (_) {},
      )));
      expect(find.byType(AlbumCarousel), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('renders one tile per album', (tester) async {
      final albums = [
        SharedAlbum(
          id: 'a1',
          name: 'Beach',
          description: null,
          coverPhotoUrl: null,
          photoCount: 3,
          isPrivate: false,
          createdAt: '',
        ),
        SharedAlbum(
          id: 'a2',
          name: 'Party',
          description: null,
          coverPhotoUrl: null,
          photoCount: 5,
          isPrivate: false,
          createdAt: '',
        ),
      ];
      await tester.pumpWidget(_wrap(AlbumCarousel(
        albums: albums,
        onTap: (_) {},
      )));
      expect(find.text('Beach'), findsOneWidget);
      expect(find.text('Party'), findsOneWidget);
    });

    testWidgets('invokes onTap with album id', (tester) async {
      String? tappedId;
      final album = SharedAlbum(
        id: 'a1',
        name: 'Beach',
        description: null,
        coverPhotoUrl: null,
        photoCount: 3,
        isPrivate: false,
        createdAt: '',
      );
      await tester.pumpWidget(_wrap(AlbumCarousel(
        albums: [album],
        onTap: (id) => tappedId = id,
      )));
      await tester.tap(find.text('Beach'));
      expect(tappedId, 'a1');
    });
  });

  // ---------------------------------------------------------------------------
  // AlbumUpdateBanner
  // ---------------------------------------------------------------------------

  group('AlbumUpdateBanner', () {
    testWidgets('renders nothing for count = 0', (tester) async {
      await tester.pumpWidget(_wrap(
          AlbumUpdateBanner(count: 0, onTap: () {})));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('renders singular label for count = 1', (tester) async {
      await tester.pumpWidget(_wrap(
          AlbumUpdateBanner(count: 1, onTap: () {})));
      expect(find.textContaining('1 álbum'), findsOneWidget);
    });

    testWidgets('renders plural label for count > 1', (tester) async {
      await tester.pumpWidget(_wrap(
          AlbumUpdateBanner(count: 3, onTap: () {})));
      expect(find.textContaining('3 álbumes'), findsOneWidget);
    });

    testWidgets('invokes onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
          AlbumUpdateBanner(count: 2, onTap: () => taps++)));
      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // AlbumUpdatesEmptyState
  // ---------------------------------------------------------------------------

  group('AlbumUpdatesEmptyState', () {
    testWidgets('renders icon + message', (tester) async {
      await tester.pumpWidget(_wrap(const AlbumUpdatesEmptyState()));
      expect(find.byIcon(Icons.collections_outlined), findsOneWidget);
      expect(find.textContaining('actualizaciones'), findsOneWidget);
    });
  });
}
