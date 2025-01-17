import 'package:json_annotation/json_annotation.dart';

part 'challenge.g.dart'; // Required for json_serializable

@JsonSerializable()
class Challenge {
  @JsonKey(name: 'challenge_id') // Maps to `challenge_id` in DB/JSON
  final int challengeId;

  @JsonKey(name: 'start_time') // Maps to `start_time` in DB/JSON
  final DateTime startTime;

  final int? duration; // Optional if DB allows NULL for `duration`

  @JsonKey(name: 'earning_points') // Maps to `earning_points` in DB/JSON
  final int? earningPoints; // Optional if DB allows NULL for `earning_points`

  final String difficulty; // Required if non-NULL in DB

  final int? length; // Optional if DB allows NULL for `length`

  Challenge({
    required this.challengeId,
    required this.startTime,
    this.duration,
    this.earningPoints,
    required this.difficulty,
    this.length,
  });

  // Factory constructor to parse JSON into the `Challenge` object
  factory Challenge.fromJson(Map<String, dynamic> json) =>
      _$ChallengeFromJson(json);

  // Method to convert `Challenge` object into JSON
  Map<String, dynamic> toJson() => _$ChallengeToJson(this);
}
