// challenge.dart
import 'package:json_annotation/json_annotation.dart';

part 'challenge.g.dart';

@JsonSerializable()
class Challenge {
  final int challengeId;
  final DateTime startTime;
  final int duration;
  final int earningPoints;
  final String difficulty;
  final String type;

  Challenge({
    required this.challengeId,
    required this.startTime,
    required this.duration,
    required this.earningPoints,
    required this.difficulty,
    required this.type,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) => _$ChallengeFromJson(json);
  Map<String, dynamic> toJson() => _$ChallengeToJson(this);
}