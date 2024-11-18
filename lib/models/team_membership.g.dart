// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_membership.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TeamMembership _$TeamMembershipFromJson(Map<String, dynamic> json) =>
    TeamMembership(
      teamId: (json['teamId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      dateJoined: DateTime.parse(json['dateJoined'] as String),
      dateLeft: json['dateLeft'] == null
          ? null
          : DateTime.parse(json['dateLeft'] as String),
    );

Map<String, dynamic> _$TeamMembershipToJson(TeamMembership instance) =>
    <String, dynamic>{
      'teamId': instance.teamId,
      'userId': instance.userId,
      'dateJoined': instance.dateJoined.toIso8601String(),
      'dateLeft': instance.dateLeft?.toIso8601String(),
    };
