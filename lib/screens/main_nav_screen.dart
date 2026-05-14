import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;

  final String _currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  final List<Widget> _screens = const [
    HomeScreen(),
    MatchesScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// Cuenta cuántos matches del usuario tienen mensajes no leídos.
  /// Un match tiene "unread" si:
  ///   - lastMessageTime != null  (hay algún mensaje)
  ///   - lastMessageSender != currentUserId  (no es mío)
  ///   - lastSeen_{currentUserId} == null  ó  lastMessageTime > lastSeen_{uid}
  int _countUnreadMatches(List<QueryDocumentSnapshot> docs) {
    int count = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lastMsgTime = data['lastMessageTime'] as Timestamp?;
      final lastSender = data['lastMessageSender'] as String?;
      final lastSeen =
          data['lastSeen_$_currentUserId'] as Timestamp?;

      if (lastMsgTime == null) continue;
      if (lastSender == _currentUserId) continue;
      if (lastSeen == null) {
        count++;
      } else if (lastMsgTime.compareTo(lastSeen) > 0) {
        count++;
      }
    }
    return count;
  }

  Widget _buildBottomNav() {
    // Stream de matches del usuario para calcular el badge en "Matches"
    final matchesStream = _currentUserId.isEmpty
        ? const Stream<QuerySnapshot>.empty()
        : FirebaseFirestore.instance
            .collection('matches')
            .where('users', arrayContains: _currentUserId)
            .snapshots();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: StreamBuilder<QuerySnapshot>(
            stream: matchesStream,
            builder: (context, snapshot) {
              final unreadCount = (snapshot.hasData)
                  ? _countUnreadMatches(snapshot.data!.docs)
                  : 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(
                    index: 0,
                    activeIcon: Icons.home_rounded,
                    inactiveIcon: Icons.home_outlined,
                    label: 'Inicio',
                  ),
                  _navItem(
                    index: 1,
                    activeIcon: Icons.chat_bubble_rounded,
                    inactiveIcon: Icons.chat_bubble_outline_rounded,
                    label: 'Matches',
                    badgeCount: unreadCount,
                  ),
                  _navItem(
                    index: 2,
                    activeIcon: Icons.person_rounded,
                    inactiveIcon: Icons.person_outline_rounded,
                    label: 'Perfil',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
    int badgeCount = 0,
  }) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isSelected
                      ? ShaderMask(
                          shaderCallback: (b) => LinearGradient(
                            colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                          ).createShader(b),
                          child: Icon(activeIcon,
                              color: Colors.white, size: 26),
                        )
                      : Icon(inactiveIcon,
                          color: Theme.of(context).textTheme.bodyMedium?.color, size: 24),
                ),
                // Badge
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: badgeCount > 9 ? 5 : 0,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                        ),
                        shape: badgeCount > 9
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                        borderRadius: badgeCount > 9
                            ? BorderRadius.circular(9)
                            : null,
                        border: Border.all(color: Theme.of(context).cardColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'InterTight',
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}