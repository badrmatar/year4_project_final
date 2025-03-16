import 'package:posthog_flutter/posthog_flutter.dart';
import 'analytics_client_base.dart';

class PosthogAnalyticsClient implements AnalyticsClientBase {
  static final Posthog _posthog = Posthog();

  const PosthogAnalyticsClient();

  @override
  Future toggleAnalyticsCollection(bool enabled) {
    if (enabled) {
      return _posthog.enable();
    } else {
      return _posthog.disable();
    }
  }

  @override
  Future identifyUser({
    required String userId,
    required String email,
    required String role,
  }) async {
    if (await _posthog.getDistinctId() == userId) return Future.value();
    return _posthog.identify(
      userId: userId,
      userProperties: {
        'email': email,
        'role': role,
      },
    );
  }

  @override
  Future resetUser() {
    return _posthog.reset();
  }

  @override
  Future trackEvent(String eventName, [Map<String, Object>? eventData]) {
    return _posthog.capture(eventName: eventName, properties: eventData);
  }

  @override
  Future trackScreenView(String routeName, String action) {
    return _posthog.screen(
      screenName: routeName,
      properties: {'action': action},
    );
  }

  @override
  Future trackNewAppOnboarding() {
    return _posthog.capture(eventName: 'user_completed_onboarding');
  }

  @override
  Future trackAppCreated() {
    return _posthog.capture(eventName: 'app_created');
  }

  @override
  Future trackAppUpdated() {
    return _posthog.capture(eventName: 'app_updated');
  }

  @override
  Future trackAppDeleted() {
    return _posthog.capture(eventName: 'app_deleted');
  }

  @override
  Future trackTaskCompleted(int completedCount) {
    return _posthog.capture(
      eventName: 'task_completed',
      properties: {
        'completed_count': completedCount,
      },
    );
  }

  @override
  Future trackAppBackgrounded() {
    return _posthog.capture(eventName: 'app_backgrounded');
  }

  @override
  Future trackAppForegrounded() {
    return _posthog.capture(eventName: 'app_foregrounded');
  }

  @override
  Future trackBottomSheetView(String routeName, [Map<String, Object>? data]) {
    return _posthog.capture(
      eventName: 'bottom_sheet_view',
      properties: {
        'route_name': routeName,
        if (data != null) ...data,
      },
    );
  }

  @override
  Future trackDialogView(String dialogName, [Map<String, Object>? data]) {
    return _posthog.capture(
      eventName: 'dialog_view',
      properties: {
        'dialog_name': dialogName,
        if (data != null) ...data,
      },
    );
  }

  @override
  Future trackButtonPressed(String buttonName, [Map<String, Object>? data]) {
    return _posthog.capture(
      eventName: 'button_pressed',
      properties: {
        'button_name': buttonName,
        if (data != null) ...data,
      },
    );
  }

  @override
  Future trackPermissionRequest(String permission, String status) {
    return _posthog.capture(
      eventName: 'permission_requested',
      properties: {
        'permission': permission,
        'status': status,
      },
    );
  }

  @override
  Future trackRunStarted(String journeyType, int challengeId) {
    return _posthog.capture(
      eventName: 'run_started',
      properties: {
        'journey_type': journeyType,
        'challenge_id': challengeId,
      },
    );
  }

  @override
  Future trackRunCompleted(String journeyType, double distanceKm, int durationSeconds) {
    return _posthog.capture(
      eventName: 'run_completed',
      properties: {
        'journey_type': journeyType,
        'distance_km': distanceKm,
        'duration_seconds': durationSeconds,
        'pace_min_per_km': durationSeconds / 60 / distanceKm,
      },
    );
  }

  @override
  Future trackRunPaused(bool isAutoPaused) {
    return _posthog.capture(
      eventName: 'run_paused',
      properties: {
        'is_auto_paused': isAutoPaused,
      },
    );
  }

  @override
  Future trackRunResumed(bool wasAutoPaused) {
    return _posthog.capture(
      eventName: 'run_resumed',
      properties: {
        'was_auto_paused': wasAutoPaused,
      },
    );
  }

  @override
  Future trackChallengeSelected(int challengeId, String difficulty, double lengthKm) {
    return _posthog.capture(
      eventName: 'challenge_selected',
      properties: {
        'challenge_id': challengeId,
        'difficulty': difficulty,
        'length_km': lengthKm,
      },
    );
  }
}