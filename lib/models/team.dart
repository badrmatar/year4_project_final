import 'package:json_annotation/json_annotation.dart';

part 'team.g.dart';

@JsonSerializable()
class Team {
  // Match DB column names via @JsonKey if your JSON returns snake_case keys
  @JsonKey(name: 'team_id')
  final int teamId;

  @JsonKey(name: 'team_name')
  final String teamName;

  // These columns are optional in case they're sometimes null
  @JsonKey(name: 'current_streak')
  final int? currentStreak;

  // If Supabase returns an ISO8601 string for the date, DateTime? should work
  // Otherwise, you can store it as String? and parse manually.
  @JsonKey(name: 'last_completion_date')
  final DateTime? lastCompletionDate;

  @JsonKey(name: 'league_room_id')
  final int? leagueRoomId;

  Team({
    required this.teamId,
    required this.teamName,
    this.currentStreak,
    this.lastCompletionDate,
    this.leagueRoomId,
  });

  // JSON serialization helpers
  factory Team.fromJson(Map<String, dynamic> json) => _$TeamFromJson(json);
  Map<String, dynamic> toJson() => _$TeamToJson(this);
}
