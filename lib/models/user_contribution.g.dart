// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_contribution.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserContribution _$UserContributionFromJson(Map<String, dynamic> json) =>
    UserContribution(
      userContributionId: (json['userContributionId'] as num).toInt(),
      teamChallengeId: (json['teamChallengeId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      startLatitude: (json['startLatitude'] as num).toDouble(),
      startLongitude: (json['startLongitude'] as num).toDouble(),
      endLatitude: (json['endLatitude'] as num).toDouble(),
      endLongitude: (json['endLongitude'] as num).toDouble(),
      contributionDetails: json['contributionDetails'] as String?,
      pointsEarned: (json['pointsEarned'] as num).toInt(),
      route: UserContribution._latLngListFromJson(json['route'] as List),
      journeyType: json['journeyType'] as String,
    );

Map<String, dynamic> _$UserContributionToJson(UserContribution instance) =>
    <String, dynamic>{
      'userContributionId': instance.userContributionId,
      'teamChallengeId': instance.teamChallengeId,
      'userId': instance.userId,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime.toIso8601String(),
      'startLatitude': instance.startLatitude,
      'startLongitude': instance.startLongitude,
      'endLatitude': instance.endLatitude,
      'endLongitude': instance.endLongitude,
      'contributionDetails': instance.contributionDetails,
      'pointsEarned': instance.pointsEarned,
      'journeyType': instance.journeyType,
      'route': UserContribution._latLngListToJson(instance.route),
    };
