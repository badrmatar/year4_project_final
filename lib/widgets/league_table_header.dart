import 'package:flutter/material.dart';

class LeagueTableHeader extends StatelessWidget {
  const LeagueTableHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 32),
            Expanded(
              flex: 3,
              child: Text(
                "TEAM",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade300,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  "PTS",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  "STREAK",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}