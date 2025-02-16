// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Team _$TeamFromJson(Map<String, dynamic> json) => Team(
      teamId: (json['team_id'] as num).toInt(),
      teamName: json['team_name'] as String,
      currentStreak: (json['current_streak'] as num?)?.toInt(),
      lastCompletionDate: json['last_completion_date'] == null
          ? null
          : DateTime.parse(json['last_completion_date'] as String),
      leagueRoomId: (json['league_room_id'] as num?)?.toInt(),
    );

Map<String, dynamic> _$TeamToJson(Team instance) => <String, dynamic>{
      'team_id': instance.teamId,
      'team_name': instance.teamName,
      'current_streak': instance.currentStreak,
      'last_completion_date': instance.lastCompletionDate?.toIso8601String(),
      'league_room_id': instance.leagueRoomId,
    };
