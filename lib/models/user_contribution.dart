import 'package:json_annotation/json_annotation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

part 'user_contribution.g.dart';

@JsonSerializable()
class UserContribution {
  final int userContributionId;
  final int teamChallengeId;
  final int userId;
  final DateTime startTime;
  final DateTime endTime;
  final double startLatitude;
  final double startLongitude;
  final double endLatitude;
  final double endLongitude;
  final String? contributionDetails;
  final int pointsEarned;
  @JsonKey(
    fromJson: _latLngListFromJson,
    toJson: _latLngListToJson,
  )
  final List<LatLng> route;

  UserContribution({
    required this.userContributionId,
    required this.teamChallengeId,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
    this.contributionDetails,
    required this.pointsEarned,
    required this.route,
  });

  factory UserContribution.fromJson(Map<String, dynamic> json) =>
      _$UserContributionFromJson(json);

  Map<String, dynamic> toJson() => _$UserContributionToJson(this);

  static List<LatLng> _latLngListFromJson(List<dynamic> json) {
    return json
        .map((point) => LatLng(
      (point['latitude'] as num).toDouble(),
      (point['longitude'] as num).toDouble(),
    ))
        .toList();
  }

  static List<Map<String, dynamic>> _latLngListToJson(List<LatLng> route) {
    return route
        .map((point) => {
      'latitude': point.latitude,
      'longitude': point.longitude,
    })
        .toList();
  }
}