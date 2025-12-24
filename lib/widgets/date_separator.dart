// lib/widgets/date_separator.dart
// ✅ 날짜 구분선 위젯

import 'package:flutter/material.dart';

class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({
    Key? key,
    required this.date,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDate(date),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) {
      return '오늘';
    } else if (targetDate == yesterday) {
      return '어제';
    } else if (now.year == date.year) {
      return '${date.month}월 ${date.day}일';
    } else {
      return '${date.year}년 ${date.month}월 ${date.day}일';
    }
  }
}