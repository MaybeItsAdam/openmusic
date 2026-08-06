import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openmusic/models/database/database.dart';

final databaseProvider = Provider((ref) => AppDatabase());
