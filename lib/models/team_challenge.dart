import 'package:json_annotation/json_annotation.dart';

part 'team_challenge.g.dart';

@JsonSerializable()
class TeamChallenge {
  final int teamChallengeId;
  final int teamId;
  final int challengeId;
  final String status;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalPointsEarned;

  TeamChallenge({
    required this.teamChallengeId,
    required this.teamId,
    required this.challengeId,
    required this.status,
    required this.startTime,
    this.endTime,
    required this.totalPointsEarned,
  });

  factory TeamChallenge.fromJson(Map<String, dynamic> json) => _$TeamChallengeFromJson(json);
  Map<String, dynamic> toJson() => _$TeamChallengeToJson(this);
}