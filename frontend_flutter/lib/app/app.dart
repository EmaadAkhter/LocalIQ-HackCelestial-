import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/fastapi_service.dart';
import '../services/mock_api_service.dart';
import 'app_state.dart';
import 'router.dart';

/// Root widget. Wires up state, theme and routing.
///
/// The app is a **presentation layer only**: it renders whatever the LocalIQ
/// FastAPI backend returns. Recommendation logic, Places search and route
/// metrics all live server-side.
///
/// Backend selection:
///  * default        -> [FastApiService] against [AppConfig.apiBaseUrl]
///  * `--dart-define=USE_MOCK_DATA=true` -> fully offline mock data
///
/// [FastApiService] already falls back to mock data per-call when the backend
/// is unreachable, so the UI never breaks mid-demo.
class LocalIQApp extends StatelessWidget {
  const LocalIQApp({this.api, super.key});

  /// Inject a custom [ApiService] in tests.
  final ApiService? api;

  @override
  Widget build(BuildContext context) {
    final ApiService service = api ?? _defaultService();
    return ChangeNotifierProvider<AppState>(
      create: (BuildContext _) => AppState(api: service),
      child: MaterialApp(
        title: 'LocalIQ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: Routes.splash,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }

  static ApiService _defaultService() {
    if (AppConfig.useMockData) {
      return MockApiService();
    }
    // Real backend; falls back to mock data per call when unreachable.
    return FastApiService(baseUrl: AppConfig.apiBaseUrl);
  }
}
