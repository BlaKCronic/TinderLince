import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;

  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1A1A1A);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textSecondary = Color(0xFFAAAAAA);

  final List<Widget> _screens = const [
    HomeScreen(),
    _ChatPlaceholder(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.home_rounded, Icons.home_outlined, 'Inicio'),
              _navItem(1, Icons.chat_bubble_rounded,
                  Icons.chat_bubble_outline_rounded, 'Matches'),
              _navItem(
                  2, Icons.person_rounded, Icons.person_outline_rounded, 'Perfil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? _pinkStart.withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isSelected
                  ? ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [_pinkStart, _orangeEnd],
                      ).createShader(b),
                      child: Icon(activeIcon,
                          color: Colors.white, size: 26),
                    )
                  : Icon(inactiveIcon, color: _textSecondary, size: 24),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isSelected ? _pinkStart : _textSecondary,
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

/// Placeholder para la pantalla de chats/matches
class _ChatPlaceholder extends StatelessWidget {
  const _ChatPlaceholder();

  static const _bg = Color(0xFF121212);
  static const _surface = Color(0xFF1E1E1E);
  static const _pinkStart = Color(0xFFFF4D6D);
  static const _orangeEnd = Color(0xFFFF8A00);
  static const _textSecondary = Color(0xFFAAAAAA);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_pinkStart, _orangeEnd],
                ).createShader(b),
                child: const Text(
                  'Matches',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.07)),
                      ),
                      child: Icon(Icons.chat_bubble_outline_rounded,
                          color: _pinkStart.withOpacity(0.5), size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Próximamente',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Los chats con tus matches\naparecerán aquí',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: _textSecondary, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}