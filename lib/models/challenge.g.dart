// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'challenge.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Challenge _$ChallengeFromJson(Map<String, dynamic> json) => Challenge(
      challengeId: (json['challengeId'] as num).toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      duration: (json['duration'] as num).toInt(),
      earningPoints: (json['earningPoints'] as num).toInt(),
      difficulty: json['difficulty'] as String,
      type: json['type'] as String,
    );

Map<String, dynamic> _$ChallengeToJson(Challenge instance) => <String, dynamic>{
      'challengeId': instance.challengeId,
      'startTime': instance.startTime.toIso8601String(),
      'duration': instance.duration,
      'earningPoints': instance.earningPoints,
      'difficulty': instance.difficulty,
      'type': instance.type,
    };
