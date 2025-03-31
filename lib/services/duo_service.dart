import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> updateDuoLocation({
  required int userId,
  required int challengeId,
  required double latitude,
  required double longitude,
}) async {
  final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/update_duo_location';
  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
    },
    body: jsonEncode({
      'user_id': userId,
      'challenge_id': challengeId,
      'latitude': latitude,
      'longitude': longitude,
    }),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Failed to update duo location: ${response.body}');
  }
}

Future<Map<String, dynamic>?> getDuoPartner({
  required int userId,
  required int challengeId,
}) async {
  final url = '${dotenv.env['SUPABASE_URL']}/functions/v1/get_duo_partner';
  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
    },
    body: jsonEncode({
      'user_id': userId,
      'challenge_id': challengeId,
    }),
  );
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data;
  }
  return null;
}
