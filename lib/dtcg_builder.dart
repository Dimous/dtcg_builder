import "dart:convert";
import "package:build/build.dart";

import "src/pipeline.dart";

final class DTCGBuilder implements Builder {
  @override
  final buildExtensions = const {
    ".tokens.json": [".tokens.g.dart"],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final pipeline = Pipeline()
      ..parse(jsonDecode(await buildStep.readAsString(buildStep.inputId)))
      ..resolve();

    await buildStep.writeAsString(buildStep.inputId.changeExtension(".g.dart"), pipeline.generate());
  }
}

//---

Builder builder(BuilderOptions options) => DTCGBuilder();
