import 'package:flutter/material.dart';
import 'services/analytics_service.dart';

class AnalyticsRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final _analytics = AnalyticsService().client;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _analytics.trackScreenView(
        route.settings.name ?? 'Unknown',
        'push',
      );
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is PageRoute && route is PageRoute) {
      _analytics.trackScreenView(
        previousRoute.settings.name ?? 'Unknown',
        'pop',
      );
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute) {
      _analytics.trackScreenView(
        newRoute.settings.name ?? 'Unknown',
        'replace',
      );
    }
  }
}