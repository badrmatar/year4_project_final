import 'package:json_annotation/json_annotation.dart';

part 'team.g.dart';

@JsonSerializable()
class Team {
  @JsonKey(name: 'team_id')
  final int teamId;

  @JsonKey(name: 'team_name')
  final String teamName;

//optional if null  @JsonKey(name: 'current_streak')
  final int? currentStreak;

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

  // JSON serialization
  factory Team.fromJson(Map<String, dynamic> json) => _$TeamFromJson(json);
  Map<String, dynamic> toJson() => _$TeamToJson(this);
}
