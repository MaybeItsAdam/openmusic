#!/usr/bin/env bash
set -euo pipefail

# Regenerates the drift schema snapshots used by test/drift/app_db/migration_test.dart.
#
# drift_dev emits default values that reference app enums (SearchMode,
# YoutubeClientEngine, ...) but only imports package:drift, so the generated
# files do not compile as-is. This script re-adds the missing imports after
# generation. Run it after changing any table definition or bumping
# schemaVersion.

cd "$(dirname "$0")/.."

schemaDir='drift_schemas/app_db'
outDir='test/drift/app_db/generated'

echo 'Dumping current schema...'
dart run drift_dev schema dump lib/models/database/database.dart "${schemaDir}/"

echo 'Generating step-by-step migration helpers...'
dart run drift_dev schema steps "${schemaDir}/" lib/models/database/database.steps.dart

echo 'Generating schema snapshots...'
dart run drift_dev schema generate "${schemaDir}/" "${outDir}/"

echo 'Inlining enum default values...'
# drift emits defaults as Constant(SomeEnum.value.name) but imports only
# package:drift, so the snapshots do not compile. Importing the enums is not a
# fix either: several of them (SourceType, SourceCodecs, SourceQualities) have
# since been deleted from the app, and a historical snapshot must not depend on
# code that is free to change. Constant(X.y.name) is exactly Constant('y'), so
# inline it and let the snapshot stand alone.
for file in "${outDir}"/schema_v*.dart; do
    perl -pi -e "s/Constant\(([A-Z][A-Za-z0-9_]*)\.([A-Za-z0-9_]+)\.name\)/Constant('\$2')/g" "${file}"
done

if grep -rqE "Constant\([A-Z][A-Za-z0-9_]*\." "${outDir}"; then
    echo 'Warning: unresolved Dart references remain in the snapshots:' >&2
    grep -rhoE "Constant\([A-Z][A-Za-z0-9_]*\." "${outDir}" | sort -u >&2
fi

echo 'Done. Run: flutter test test/drift/app_db/migration_test.dart'
