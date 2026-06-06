import "package:dart_style/dart_style.dart";
import "package:code_builder/code_builder.dart";

import "utils.dart";
import "models.dart";

/**
 * @todo композит
 * https://www.designtokens.org/tr/drafts/format/
 */
final class Pipeline {
  void resolve() {
    for (final token in _registry.values) {
      token.resolvedValue = _resolve(token.rawValue, {});
    }
  }

  //---

  void parse(Map<String, dynamic> json) => _parse(json, _root);

  //---

  String generate() => DartFormatter(languageVersion: DartFormatter.latestLanguageVersion).format(
    Library(
      (builder) => builder
        ..directives.addAll([
          Directive.import("package:flutter/widgets.dart", hide: ["BoxShadow"]),
          Directive.import("package:flutter_inset_shadow/flutter_inset_shadow.dart"),
        ])
        ..body.addAll([
          ..._registry.values.map(
            (token) => Field(
              (builder) => builder
                ..name = token.name
                ..modifier = FieldModifier.final$
                ..assignment = _toExpression(token.resolvedValue, token.type).code,
            ),
          ),
          ..._root.children.entries.map(
            (entry) => Field(
              (builder) => builder
                ..modifier = FieldModifier.final$
                ..name = "\$${entry.key.name}"
                ..assignment = (entry.value is Token ? refer((entry.value as Token).name) : _buildRecordLiteral(entry.value as Group)).code,
            ),
          ),
        ]),
    ).accept(DartEmitter(useNullSafetySyntax: true)).toString(),
  );

  //---

  dynamic _resolve(dynamic value, Set<String> visited) {
    if (value is String && value.startsWith("{") && value.endsWith("}")) {
      final path = value.substring(1, value.length - 1);

      if (visited.contains(path)) {
        throw Exception("Circular reference detected: $path");
      }

      final target = _registry[path];

      if (null == target) {
        throw Exception("Reference not found: $path");
      }

      return target;
    }

    if (value is List) {
      return value.map((value) => _resolve(value, visited)).toList();
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key, _resolve(value, visited)));
    }

    return value;
  }

  //---

  void _parse(Map<String, dynamic> json, Group parent) {
    final inheritedType = json[r"$type"] as String? ?? parent.type;

    json.forEach((key, value) {
      if (!key.startsWith(r"$")) {
        final currentPath = [...parent.path, key];

        if (value is Map<String, dynamic> && value.containsKey(r"$value")) {
          final tokenType = value[r"$type"] as String? ?? inheritedType;

          if (null == tokenType) {
            throw Exception("W3C Violation: Missing \$type at ${currentPath.join(".")}");
          }

          _registry[currentPath.join(".")] = parent.children[key] = Token(currentPath, tokenType, value[r"$value"]);
        } else if (value is Map<String, dynamic>) {
          _parse(value, parent.children[key] = Group(currentPath, inheritedType));
        }
      }
    });
  }

  //---

  Expression _buildColor(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("W3C Color must be an object: $value");
    }

    final $hex = value["hex"];
    final $alpha = value["alpha"];
    final $components = value["components"];
    final $colorSpace = value["colorSpace"];

    if ($colorSpace is! String) {
      throw ArgumentError("Color missing 'colorSpace': $value");
    }

    if ($components is! List) {
      throw ArgumentError("Color 'components' must be a list: $value");
    }

    if ("srgb" == $colorSpace) {
      if (3 != $components.length) {
        throw ArgumentError("srgb color must have exactly 3 components: $value");
      }

      return _colorFromARGB(_normalizeAlpha($alpha), _normalizeChannel($components[0]), _normalizeChannel($components[1]), _normalizeChannel($components[2]));
    }

    if ($hex is String) {
      final fallback = _parseHex($hex);

      return _colorFromARGB(_normalizeAlpha($alpha), (fallback >> 16) & 0xff, (fallback >> 8) & 0xff, fallback & 0xff);
    }

    throw UnsupportedError("Unsupported colorSpace without hex fallback: ${$colorSpace}");
  }

  //---

  Expression _buildShadow(dynamic value) {
    value = _unwrapValue(value);

    if (value is List) {
      return literalList(value.map(_buildShadow).toList());
    }

    if (value is! Map) {
      throw ArgumentError("Shadow must be a map: $value");
    }

    if (!value.containsKey("color") || !value.containsKey("offsetX") || !value.containsKey("offsetY") || !value.containsKey("blur") || !value.containsKey("spread")) {
      throw ArgumentError("Shadow missing required properties: $value");
    }

    final $inset = value["inset"];

    return refer("BoxShadow", "package:flutter_inset_shadow/flutter_inset_shadow.dart").call([], {
      "color": _toExpression(value["color"], "color"),
      "blurRadius": _toExpression(value["blur"], "dimension"),
      "spreadRadius": _toExpression(value["spread"], "dimension"),
      if (null != $inset && $inset is bool) "inset": literalBool($inset),
      "offset": refer("Offset").call([_toExpression(value["offsetX"], "dimension"), _toExpression(value["offsetY"], "dimension")]),
    });
  }

  //---

  Expression _buildBorder(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("Border must be a map: $value");
    }

    if (!value.containsKey("color") || !value.containsKey("width") || !value.containsKey("style")) {
      throw ArgumentError("Border missing required properties: $value");
    }

    final $style = value["style"];

    if ($style is Map) {
      throw UnsupportedError("Complex stroke styles are not supported: ${$style}");
    }

    return refer("BorderSide").call([], {"color": _toExpression(value["color"], "color"), "width": _toExpression(value["width"], "dimension"), "style": _toExpression($style, "strokeStyle")});
  }

  //---

  Expression _buildNumber(dynamic value) {
    value = _unwrapValue(value);

    if (value is! num) {
      throw ArgumentError("Number must be a JSON number: $value");
    }

    return literalNum(value);
  }

  //---

  Expression _buildDuration(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("Duration must be an object: $value");
    }

    final $unit = value["unit"];
    final $value = value["value"];

    if ($value is! num) {
      throw ArgumentError("Duration 'value' must be a number: $value");
    }

    if ($unit is! String || !["s", "ms"].contains($unit)) {
      throw ArgumentError("Duration 'unit' must be 'ms' or 's': $value");
    }

    final milliseconds = switch ($unit) {
      "ms" => $value,

      "s" => 1000 * $value,

      _ => throw ArgumentError("Unsupported duration unit: ${$unit}"),
    };

    return refer("Duration").call([], {"milliseconds": literalNum(milliseconds.round())});
  }

  //---

  /**
   * в спеке больше разновидностей
   */
  Expression _buildGradient(dynamic value) {
    value = _unwrapValue(value);

    if (value is! List) {
      throw ArgumentError("Gradient must be an array: $value");
    }

    final stops = <Expression>[];
    final colors = <Expression>[];

    for (final item in value) {
      final resolved = _unwrapValue(item);

      if (resolved is! Map) {
        throw ArgumentError("Gradient stop must be an object: $item");
      }

      if (!resolved.containsKey("color") || !resolved.containsKey("position")) {
        throw ArgumentError("Gradient stop missing properties: $resolved");
      }

      final position = resolved["position"] is num ? (resolved["position"] as num).clamp(0, 1) : null;

      stops.add(null != position ? literalNum(position) : _toExpression(resolved["position"], "number"));

      colors.add(_toExpression(resolved["color"], "color"));
    }

    return refer("LinearGradient").call([], {"colors": literalList(colors), "stops": literalList(stops)});
  }

  //---

  Expression _buildDimension(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("Dimension must be an object: $value");
    }

    final $unit = value["unit"];
    final $value = value["value"];

    if ($value is! num) {
      throw ArgumentError("Dimension 'value' must be a number: $value");
    }

    if ($unit is! String || !["px", "rem"].contains($unit)) {
      throw ArgumentError("Dimension 'unit' must be 'px' or 'rem': $value");
    }

    return switch ($unit) {
      "px" => literalNum($value),

      "rem" => literalNum(16 * $value),

      _ => throw ArgumentError("Unsupported dimension unit: ${$unit}"),
    };
  }

  //---

  Expression _buildFontFamily(dynamic value) {
    value = _unwrapValue(value);

    if (value is String) {
      return literalString(value);
    }

    if (value is List) {
      if (value.every((value) => value is String)) {
        if (value.isEmpty) {
          throw ArgumentError("fontFamily array cannot be empty");
        }

        return literalString(value.first);
      }

      throw ArgumentError("fontFamily array must contain only strings: $value");
    }

    throw ArgumentError("fontFamily must be a string or list of strings: $value");
  }

  //---

  Expression _buildFontWeight(dynamic value) {
    value = _unwrapValue(value);

    if (value is num) {
      final weight = value.round();

      if (100 > weight || 900 < weight || 0 != weight % 100) {
        throw ArgumentError("Flutter supports fontWeight from 100 to 900 in steps of 100: $value");
      }

      return refer("FontWeight").property("w$weight");
    }

    if (value is String) {
      final mapped = switch (value.toLowerCase()) {
        "bold" => 700,

        "light" => 300,

        "medium" => 500,

        "thin" || "hairline" => 100,

        "semi-bold" || "demi-bold" => 600,

        "extra-bold" || "ultra-bold" => 800,

        "extra-light" || "ultra-light" => 200,

        "normal" || "regular" || "book" => 400,

        "black" || "heavy" || "extra-black" || "ultra-black" => 900,

        _ => throw ArgumentError("Unknown fontWeight name: $value"),
      };

      return refer("FontWeight").property("w$mapped");
    }

    throw ArgumentError("fontWeight must be a number or string: $value");
  }

  //---

  Expression _buildTypography(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("Typography must be an object: $value");
    }

    for (final key in ["fontSize", "lineHeight", "fontFamily", "fontWeight", "letterSpacing"]) {
      if (!value.containsKey(key)) {
        throw ArgumentError("Typography missing '$key': $value");
      }
    }

    return refer("TextStyle").call([], {"height": _toExpression(value["lineHeight"], "number"), "fontSize": _toExpression(value["fontSize"], "dimension"), "fontFamily": _toExpression(value["fontFamily"], "fontFamily"), "fontWeight": _toExpression(value["fontWeight"], "fontWeight"), "letterSpacing": _toExpression(value["letterSpacing"], "dimension")});
  }

  //---

  /**
   * во Flutter нет единого слоя абстракции для Transition, поэтому возвращается карта
   */
  Expression _buildTransition(dynamic value) {
    value = _unwrapValue(value);

    if (value is! Map) {
      throw ArgumentError("Transition must be an object: $value");
    }

    for (final key in ["delay", "duration", "timingFunction"]) {
      if (!value.containsKey(key)) {
        throw ArgumentError("Transition missing '$key': $value");
      }
    }

    return literalMap({"duration": _toExpression(value["duration"], "duration"), "delay": _toExpression(value["delay"], "duration"), "curve": _toExpression(value["timingFunction"], "cubicBezier")});
  }

  //---

  Expression _buildCubicBezier(dynamic value) {
    value = _unwrapValue(value);

    if (value is! List || 4 != value.length) {
      throw ArgumentError("cubicBezier must be an array of 4 numbers: $value");
    }

    if (!value.every((value) => value is num)) {
      throw ArgumentError("cubicBezier must contain only numbers: $value");
    }

    final $x1 = value[0] as num;
    final $y1 = value[1] as num;
    final $x2 = value[2] as num;
    final $y2 = value[3] as num;

    if (0 > $x1 || 1 < $x1 || 0 > $x2 || 1 < $x2) {
      throw ArgumentError("cubicBezier x values must be in range [0,1]: $value");
    }

    return refer("Cubic").call([literalNum($x1), literalNum($y1), literalNum($x2), literalNum($y2)]);
  }

  //---

  Expression _buildStrokeStyle(dynamic value) {
    value = _unwrapValue(value);

    if (value is String) {
      return refer("BorderStyle").property(switch (value) {
        "none" => "none",

        "solid" => "solid",

        "ridge" => "solid",

        "inset" => "solid",

        "dashed" => "solid",

        "dotted" => "solid",

        "double" => "solid",

        "groove" => "solid",

        "outset" => "solid",

        _ => throw ArgumentError("Unknown strokeStyle: $value"),
      });
    }

    if (value is Map) {
      throw UnsupportedError("Object strokeStyle is not supported: $value");
    }

    throw ArgumentError("Invalid strokeStyle: $value");
  }

  //---

  /**
   * https://www.designtokens.org/schemas/2025.10/format/tokenType.json
   */
  Expression _provideBuilder(String? type, dynamic value) => switch (type) {
    "color" => _buildColor(value),

    "shadow" => _buildShadow(value),

    "border" => _buildBorder(value),

    "number" => _buildNumber(value),

    "duration" => _buildDuration(value),

    "gradient" => _buildGradient(value),

    "dimension" => _buildDimension(value),

    "fontFamily" => _buildFontFamily(value),

    "fontWeight" => _buildFontWeight(value),

    "typography" => _buildTypography(value),

    "transition" => _buildTransition(value),

    "cubicBezier" => _buildCubicBezier(value),

    "strokeStyle" => _buildStrokeStyle(value),

    _ => _buildPrimitiveLiteral(value),
  };

  //---

  int _parseHex(String hex) {
    hex = hex.replaceFirst("#", "");

    if (6 == hex.length) {
      return int.parse(hex, radix: 16);
    }

    throw ArgumentError("Hex must be 6-digit format: $hex");
  }

  //---

  int _normalizeAlpha(dynamic value) {
    if (null == value) {
      return 255;
    }

    if (value is num) {
      if (0 > value || 1 < value) {
        throw ArgumentError("Alpha out of range [0..1]: $value");
      }

      return (value * 255).round();
    }

    throw ArgumentError("Alpha must be a number: $value");
  }

  //---

  int _normalizeChannel(dynamic value) {
    if ("none" == value) {
      throw UnsupportedError("'none' is not supported in srgb components");
    }

    if (value is num) {
      if (0 > value || 1 < value) {
        throw ArgumentError("Color component out of range [0..1]: $value");
      }

      return (value * 255).round();
    }

    throw ArgumentError("Color component must be a number: $value");
  }

  //---

  Expression _colorFromARGB(int a, int r, int g, int b) => refer("Color").call([literalNum((a << 24) | (r << 16) | (g << 8) | b)]);

  //---

  Expression _toExpression(dynamic value, [String? type]) {
    if (value is Token) {
      return refer(value.name);
    }

    if (value is Map && value.containsKey(r"$value")) {
      return _toExpression(value[r"$value"], (value[r"$type"] as String?) ?? type);
    }

    return _provideBuilder(type, value);
  }

  //---

  Expression _buildPrimitiveLiteral(dynamic value) {
    if (value is List) {
      return literalList(value.map(_toExpression).toList());
    }

    if (value is Map) {
      return literalRecord([], {for (final entry in value.entries) "\$${entry.key.name}": _toExpression(entry.value)});
    }

    return literalNull;
  }

  //---

  Expression _buildRecordLiteral(Group node) => literalRecord([], {
    for (final entry in node.children.entries)
      "\$${entry.key.name}": switch (entry.value) {
        Token(:final name) => refer(name),

        final Group group => _buildRecordLiteral(group),
      },
  });
  //---

  T _unwrapValue<T>(dynamic value) {
    value = value is Token ? value.rawValue : value;

    if (value is! T) {
      throw ArgumentError("Expected $T but got ${value.runtimeType}: $value");
    }

    return value;
  }

  //---

  final _root = Group([], null);
  final _registry = <String, Token>{};
}
