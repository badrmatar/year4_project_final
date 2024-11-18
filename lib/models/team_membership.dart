import 'package:json_annotation/json_annotation.dart';

part 'team_membership.g.dart';

@JsonSerializable()
class TeamMembership {
  final int teamId;
  final int userId;
  final DateTime dateJoined;
  final DateTime? dateLeft;

  TeamMembership({
    required this.teamId,
    required this.userId,
    required this.dateJoined,
    this.dateLeft,
  });

  factory TeamMembership.fromJson(Map<String, dynamic> json) => _$TeamMembershipFromJson(json);
  Map<String, dynamic> toJson() => _$TeamMembershipToJson(this);
}