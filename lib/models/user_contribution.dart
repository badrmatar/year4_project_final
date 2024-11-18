import 'package:json_annotation/json_annotation.dart';

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
  });

  factory UserContribution.fromJson(Map<String, dynamic> json) => _$UserContributionFromJson(json);
  Map<String, dynamic> toJson() => _$UserContributionToJson(this);
}