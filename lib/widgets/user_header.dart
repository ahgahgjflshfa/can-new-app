import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/app_colors.dart';

class UserHeader extends StatelessWidget {
  const UserHeader({required this.user, super.key});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final scope = user.stationId ?? user.sectionId ?? '未設定站別';
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$scope · ${user.role}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
