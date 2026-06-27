import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DoseCard extends StatelessWidget {
  final Map<String, dynamic> dose;

  DoseCard(this.dose);

  @override
  Widget build(BuildContext context) {
    // Convert start and end times to DateTime objects
    final startTime = DateFormat('HH:mm:ss').parse(dose['start_time']);
    final endTime = DateFormat('HH:mm:ss').parse(dose['end_time']);

    // Calculate the duration of the dose in minutes
    final duration = endTime.difference(startTime).inMinutes;

    // Convert the duration into a height (based on 1440 minutes in a full day or a 24-hour scale)
    final height = (duration / 1440.0) * 100.0; // height as a percentage of total available space (100%)

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      height: height, // Dynamic height based on the time difference
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dose['name'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${dose['start_time']} - ${dose['end_time']}',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
