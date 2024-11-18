// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_challenge.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TeamChallenge _$TeamChallengeFromJson(Map<String, dynamic> json) =>
    TeamChallenge(
      teamChallengeId: (json['teamChallengeId'] as num).toInt(),
      teamId: (json['teamId'] as num).toInt(),
      challengeId: (json['challengeId'] as num).toInt(),
      status: json['status'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      totalPointsEarned: (json['totalPointsEarned'] as num).toInt(),
    );

Map<String, dynamic> _$TeamChallengeToJson(TeamChallenge instance) =>
    <String, dynamic>{
      'teamChallengeId': instance.teamChallengeId,
      'teamId': instance.teamId,
      'challengeId': instance.challengeId,
      'status': instance.status,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'totalPointsEarned': instance.totalPointsEarned,
    };
