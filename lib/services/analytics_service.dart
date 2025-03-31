import 'analytics_client_base.dart';
import 'posthog_analytics_client.dart';


class AnalyticsService {
  static AnalyticsService? _instance;
  late final AnalyticsClientBase _client;

  factory AnalyticsService() {
    _instance ??= AnalyticsService._internal();
    return _instance!;
  }

  AnalyticsService._internal() {
    _client = const PosthogAnalyticsClient();
  }

  AnalyticsClientBase get client => _client;
}