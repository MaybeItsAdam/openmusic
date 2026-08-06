// Fails if any git dependency in pubspec.yaml is on a mutable ref.
//
// A git dependency without an explicit commit `ref` tracks whatever the default
// branch points at, so the code that builds today is not the code that builds
// tomorrow. Several of these packages (the hetu_* family) ship precompiled
// bytecode that is loaded into the plugin VM with host bindings, so a moved
// branch is arbitrary code execution with no review step.
//
// Run: dart run scripts/check_pinned_deps.dart
//
// To update a pin: `flutter pub upgrade`, read the upstream diff, then copy the
// new resolved-ref values from pubspec.lock into pubspec.yaml and commit both.

import 'dart:io';

import 'package:yaml/yaml.dart';

final _sha = RegExp(r'^[0-9a-f]{40}$');

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final problems = <String>[];

  for (final section in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    final deps = pubspec[section];
    if (deps is! YamlMap) continue;

    deps.forEach((name, spec) {
      if (spec is! YamlMap) return;
      final git = spec['git'];
      if (git == null) return;

      // `git: <url>` shorthand can never carry a ref.
      if (git is! YamlMap) {
        problems.add('$section/$name: uses the git shorthand, which cannot pin');
        return;
      }

      final ref = git['ref'];
      if (ref == null) {
        problems.add('$section/$name: no ref, tracks the default branch');
      } else if (!_sha.hasMatch(ref.toString())) {
        problems.add('$section/$name: ref "$ref" is mutable, not a commit');
      }
    });
  }

  if (problems.isEmpty) {
    stdout.writeln('All git dependencies are pinned to commit SHAs.');
    return;
  }

  stderr.writeln('Unpinned git dependencies:\n');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  stderr.writeln(
    '\nPin each to the resolved-ref recorded in pubspec.lock.',
  );
  exit(1);
}
