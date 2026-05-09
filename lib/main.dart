import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_nav_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      
      /* primer intento de tema dinámico, pero no funciona bien con el sistema del celular*/
      title: 'Lince App',
      theme: LinceThemes.lightTheme, // Tema claro
      darkTheme: LinceThemes.darkTheme, // Tema oscuro
      themeMode: ThemeMode.system, // Cambia automáticamente según el celular
      home: const AuthGate(),
      
      /* tema fijo, sin cambios dinámicos hardcodeado al oscuro
      title: 'Lince',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D6D),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'InterTight',
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const AuthGate(),*/
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFFFF4D6D)),
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          return const MainNavScreen();   // ← ahora apunta a la nav principal
        }
        return const LoginScreen();
      },
    );
  }
}

class LinceThemes {
  // Colores base que se mantienen en ambos (Identidad de marca)
  static const Color pinkStart = Color(0xFFFF4D6D);
  static const Color orangeEnd = Color(0xFFFF8A00);

  // TEMA OSCURO (El original)
  static final darkTheme = ThemeData(
    colorScheme: ColorScheme.dark(
      primary: pinkStart,
      secondary: orangeEnd,
    ),
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Color(0xFFAAAAAA)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: Color(0xFF252525),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.white10) ,
      ),
    ),
    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      buttonColor: pinkStart,
      textTheme: ButtonTextTheme.primary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF333333), // Gris oscuro para el botón de cerrar
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );

  // TEMA CLARO (El nuevo)
  static final lightTheme = ThemeData(
    colorScheme: ColorScheme.light(
      primary: pinkStart,
      secondary: orangeEnd,
    ),
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5), // Blanco hueso
    cardColor: Colors.white,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF121212)), // Texto casi negro
      bodyMedium: TextStyle(color: Color(0xFF666666)), // Gris suave
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      iconTheme: IconThemeData(color: Color(0xFF121212)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: Color(0xFFF5F5F5),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.black12),
      ),
    ),
    buttonTheme: ButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      buttonColor: pinkStart,
      textTheme: ButtonTextTheme.primary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE0E0E0), // Gris claro para el botón de cerrar
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark; // Estado inicial

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    _themeMode = (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;
    notifyListeners(); // Notifica a toda la app para que se repinte
  }
}