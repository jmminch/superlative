import 'dart:io';
import 'dart:math';

import 'package:yaml/yaml.dart';

import 'superlatives_game.dart';

class ContentValidationException implements Exception {
  final String message;

  const ContentValidationException(this.message);

  @override
  String toString() => 'ContentValidationException: $message';
}

class CategoryContent {
  final String id;
  final String label;
  final List<SuperlativePrompt> superlatives;

  CategoryContent({
    required this.id,
    required this.label,
    required List<SuperlativePrompt> superlatives,
  }) : superlatives = List.unmodifiable(List.of(superlatives)) {
    if (id.trim().isEmpty) {
      throw const ContentValidationException('Category id must not be empty.');
    }
    if (label.trim().isEmpty) {
      throw const ContentValidationException(
          'Category label must not be empty.');
    }
    if (superlatives.isEmpty) {
      throw const ContentValidationException(
          'Category must include at least one superlative.');
    }
  }
}

class RoundContent {
  final String categoryId;
  final String categoryLabel;
  final List<SuperlativePrompt> superlatives;

  RoundContent({
    required this.categoryId,
    required this.categoryLabel,
    required List<SuperlativePrompt> superlatives,
  }) : superlatives = List.unmodifiable(List.of(superlatives));
}

abstract class ContentProvider {
  List<CategoryContent> get categories;

  RoundContent selectRoundContent({
    required RoomConfig config,
    required Random random,
    Set<String> excludeCategoryIds,
  });
}

class YamlContentProvider implements ContentProvider {
  @override
  final List<CategoryContent> categories;

  YamlContentProvider._(this.categories);

  static Future<YamlContentProvider> fromFile(String path) async {
    var text = await File(path).readAsString();
    return fromYamlString(text);
  }

  static YamlContentProvider fromYamlString(String yamlText) {
    dynamic root;
    try {
      root = loadYaml(yamlText);
    } catch (e) {
      throw ContentValidationException('Invalid YAML: $e');
    }

    if (root is! YamlMap) {
      throw const ContentValidationException('Root YAML must be a map/object.');
    }

    var categoriesNode = root['categories'];
    if (categoriesNode is! YamlList || categoriesNode.isEmpty) {
      throw const ContentValidationException(
          'YAML must include a non-empty categories list.');
    }

    var categoryList = <CategoryContent>[];
    var categoryIds = <String>{};

    for (var i = 0; i < categoriesNode.length; i++) {
      var node = categoriesNode[i];
      if (node is! YamlMap) {
        throw ContentValidationException('Category[$i] must be a map/object.');
      }

      var id = _readRequiredString(node, 'id', context: 'Category[$i]');
      var label = _readRequiredString(node, 'label', context: 'Category[$i]');
      if (categoryIds.contains(id)) {
        throw ContentValidationException('Duplicate category id "$id".');
      }
      categoryIds.add(id);

      var rawSuperlatives = node['superlatives'];
      if (rawSuperlatives is! YamlList || rawSuperlatives.isEmpty) {
        throw ContentValidationException(
            'Category "$id" must include a non-empty superlatives list.');
      }

      var prompts = <SuperlativePrompt>[];
      var normalizedPromptTexts = <String>{};
      for (var s = 0; s < rawSuperlatives.length; s++) {
        var promptTextRaw = rawSuperlatives[s];
        if (promptTextRaw is! String || promptTextRaw.trim().isEmpty) {
          throw ContentValidationException(
              'Category "$id" superlative[$s] must be a non-empty string.');
        }

        var promptText = promptTextRaw.trim();
        var normalizedPrompt = promptText.toLowerCase();
        if (!normalizedPromptTexts.add(normalizedPrompt)) {
          throw ContentValidationException(
              'Category "$id" has duplicate superlative "$promptText".');
        }
        prompts.add(
          SuperlativePrompt(
            superlativeId: '${id}_s${s + 1}',
            promptText: promptText,
          ),
        );
      }

      categoryList.add(
        CategoryContent(id: id, label: label, superlatives: prompts),
      );
    }

    return YamlContentProvider._(List.unmodifiable(categoryList));
  }

  void validateForConfig(RoomConfig config) {
    if (categories.isEmpty) {
      throw const ContentValidationException('No categories available.');
    }

    var requiredCount = requiredPromptCount(config);
    var invalid = categories
        .where((c) => c.superlatives.length < requiredCount)
        .map((c) => c.id)
        .toList(growable: false);
    if (invalid.isNotEmpty) {
      throw ContentValidationException(
        'Categories with fewer than $requiredCount superlatives: '
        '${invalid.join(', ')}.',
      );
    }
  }

  @override
  RoundContent selectRoundContent({
    required RoomConfig config,
    required Random random,
    Set<String> excludeCategoryIds = const {},
  }) {
    if (categories.isEmpty) {
      throw const ContentValidationException('No categories available.');
    }

    var requiredCount = requiredPromptCount(config);
    var eligible = categories
        .where((c) => c.superlatives.length >= requiredCount)
        .toList(growable: false);

    if (eligible.isEmpty) {
      throw ContentValidationException(
        'No category has at least $requiredCount superlatives.',
      );
    }

    var preferred = eligible
        .where((c) => !excludeCategoryIds.contains(c.id))
        .toList(growable: false);

    var pool = preferred.isNotEmpty ? preferred : eligible;
    var category = pool[random.nextInt(pool.length)];

    var prompts = List<SuperlativePrompt>.of(category.superlatives);
    prompts.shuffle(random);
    prompts = prompts.take(requiredCount).toList(growable: false);

    return RoundContent(
      categoryId: category.id,
      categoryLabel: category.label,
      superlatives: prompts,
    );
  }

  static String _readRequiredString(
    YamlMap map,
    String key, {
    required String context,
  }) {
    var raw = map[key];
    if (raw is! String) {
      throw ContentValidationException(
          '$context field "$key" must be a string.');
    }

    var value = raw.trim();
    if (value.isEmpty) {
      throw ContentValidationException(
          '$context field "$key" must be non-empty.');
    }

    return value;
  }

  static int requiredPromptCount(RoomConfig config) {
    return config.setCount * config.promptsPerSet;
  }
}
