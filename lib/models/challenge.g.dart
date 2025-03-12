// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'challenge.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Challenge _$ChallengeFromJson(Map<String, dynamic> json) => Challenge(
      challengeId: (json['challenge_id'] as num).toInt(),
      startTime: DateTime.parse(json['start_time'] as String),
      duration: (json['duration'] as num?)?.toInt(),
      earningPoints: (json['earning_points'] as num?)?.toInt(),
      difficulty: json['difficulty'] as String,
      length: (json['length'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ChallengeToJson(Challenge instance) => <String, dynamic>{
      'challenge_id': instance.challengeId,
      'start_time': instance.startTime.toIso8601String(),
      'duration': instance.duration,
      'earning_points': instance.earningPoints,
      'difficulty': instance.difficulty,
      'length': instance.length,
    };
