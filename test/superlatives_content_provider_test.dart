import 'dart:math';

import 'package:test/test.dart';

import '../bin/content_provider.dart';
import '../bin/superlatives_game.dart';

void main() {
  group('YamlContentProvider load/validation', () {
    test('loads categories from valid YAML', () {
      var yaml = '''
categories:
  - id: animals
    label: Animals
    superlatives:
      - Cutest
      - Loudest
      - Funniest
''';

      var provider = YamlContentProvider.fromYamlString(yaml);
      expect(provider.categories.length, 1);
      expect(provider.categories.first.id, 'animals');
      expect(provider.categories.first.superlatives.length, 3);
      expect(provider.categories.first.superlatives.first.superlativeId,
          'animals_s1');
    });

    test('rejects missing categories list', () {
      expect(
        () => YamlContentProvider.fromYamlString('title: nope'),
        throwsA(isA<ContentValidationException>()),
      );
    });

    test('rejects empty category label', () {
      var yaml = '''
categories:
  - id: animals
    label: ''
    superlatives:
      - Cutest
''';

      expect(
        () => YamlContentProvider.fromYamlString(yaml),
        throwsA(isA<ContentValidationException>()),
      );
    });

    test('rejects category with empty superlative prompt', () {
      var yaml = '''
categories:
  - id: animals
    label: Animals
    superlatives:
      - Cutest
      - ''
''';

      expect(
        () => YamlContentProvider.fromYamlString(yaml),
        throwsA(isA<ContentValidationException>()),
      );
    });
  });

  group('Round selection', () {
    var provider = YamlContentProvider.fromYamlString('''
categories:
  - id: animals
    label: Animals
    superlatives:
      - Cutest
      - Loudest
      - Funniest
      - Fastest
  - id: foods
    label: Foods
    superlatives:
      - Tastiest
      - Messiest
      - Cheapest
      - Spiciest
''');

    test('selects votePhasesPerRound superlatives without replacement', () {
      var content = provider.selectRoundContent(
        config: const RoomConfig(votePhasesPerRound: 3),
        random: Random(42),
      );

      expect(content.superlatives.length, 3);
      var ids = content.superlatives.map((s) => s.superlativeId).toSet();
      expect(ids.length, 3);
    });

    test('prefers categories not in excludeCategoryIds', () {
      var content = provider.selectRoundContent(
        config: const RoomConfig(votePhasesPerRound: 3),
        random: Random(1),
        excludeCategoryIds: const {'animals'},
      );

      expect(content.categoryId, 'foods');
    });

    test('falls back to excluded categories if needed', () {
      var content = provider.selectRoundContent(
        config: const RoomConfig(votePhasesPerRound: 3),
        random: Random(1),
        excludeCategoryIds: const {'animals', 'foods'},
      );

      expect(['animals', 'foods'], contains(content.categoryId));
    });

    test('throws when no category has enough superlatives', () {
      var smallProvider = YamlContentProvider.fromYamlString('''
categories:
  - id: tiny
    label: Tiny
    superlatives:
      - One
      - Two
''');

      expect(
        () => smallProvider.selectRoundContent(
          config: const RoomConfig(votePhasesPerRound: 3),
          random: Random(1),
        ),
        throwsA(isA<ContentValidationException>()),
      );
    });
  });
}
