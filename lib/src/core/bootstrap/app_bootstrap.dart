import 'package:flutter_riverpod/flutter_riverpod.dart';

final appBootstrapProvider = FutureProvider<void>((ref) async {
  await Future<void>.value();
});
