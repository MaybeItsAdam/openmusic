import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf.dart';

final pipelineProvider = Provider((ref) {
  var pipeline = const Pipeline();
  if (kDebugMode) {
    // Pipeline is immutable: the previous code discarded the returned Pipeline,
    // so this middleware never actually ran.
    pipeline = pipeline.addMiddleware(logRequests());
  }
  return pipeline;
});
