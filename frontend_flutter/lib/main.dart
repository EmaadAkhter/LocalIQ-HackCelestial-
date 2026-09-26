import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/runtime_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeConfig.load();
  runApp(const LocalIQApp());
}
