import 'package:json_annotation/json_annotation.dart';

part 'challenge.g.dart'; // Required for json_serializable

@JsonSerializable()
class Challenge {
  @JsonKey(name: 'challenge_id')
  final int challengeId;

  @JsonKey(name: 'start_time')
  final DateTime startTime;

  final int? duration;

  @JsonKey(name: 'earning_points')
  final int? earningPoints;

  final String difficulty;

  final double? length;

  Challenge({
    required this.challengeId,
    required this.startTime,
    this.duration,
    this.earningPoints,
    required this.difficulty,
    this.length,
  });

  String get formattedDistance {
    if (length == null) return 'Distance: N/A';
    return 'Distance: ${length?.toStringAsFixed(1)} km';
  }

  factory Challenge.fromJson(Map<String, dynamic> json) =>
      _$ChallengeFromJson(json);

  Map<String, dynamic> toJson() => _$ChallengeToJson(this);
}