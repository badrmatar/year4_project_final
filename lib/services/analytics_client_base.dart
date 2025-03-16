abstract class AnalyticsClientBase {
  Future toggleAnalyticsCollection(bool enabled);
  Future identifyUser({
    required String userId,
    required String email,
    required String role,
  });
  Future resetUser();
  Future trackEvent(String eventName, [Map<String, Object>? eventData]);
  Future trackScreenView(String routeName, String action);
  Future trackNewAppOnboarding();
  Future trackAppCreated();
  Future trackAppUpdated();
  Future trackAppDeleted();
  Future trackTaskCompleted(int completedCount);
  Future trackAppBackgrounded();
  Future trackAppForegrounded();
  Future trackBottomSheetView(String routeName, [Map<String, Object>? data]);
  Future trackDialogView(String dialogName, [Map<String, Object>? data]);
  Future trackButtonPressed(String buttonName, [Map<String, Object>? data]);
  Future trackPermissionRequest(String permission, String status);

  // Added methods
  Future trackRunStarted(String journeyType, int challengeId);
  Future trackRunCompleted(String journeyType, double distanceKm, int durationSeconds);
  Future trackRunPaused(bool isAutoPaused);
  Future trackRunResumed(bool wasAutoPaused);
  Future trackChallengeSelected(int challengeId, String difficulty, double lengthKm);
}