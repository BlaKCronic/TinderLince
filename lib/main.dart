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
  
  runApp(const MainApp());
}

// 1. Convertimos MainApp en StatefulWidget para manejar el estado del tema
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();

  // 2. Este método estático permite que ProfileScreen llame a 'changeTheme'
  static MainAppState of(BuildContext context) => 
      context.findAncestorStateOfType<MainAppState>()!;
}

class MainAppState extends State<MainApp> {
  // 3. Variable de estado que controla el tema (inicia en oscuro por defecto)
  ThemeMode _themeMode = ThemeMode.dark;

  // 4. Función que será llamada por el botón del perfil
  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ajustamos el estilo de la barra de sistema según el tema elegido
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _themeMode == ThemeMode.light 
            ? Brightness.dark 
            : Brightness.light,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lince App',
      // Usamos los temas que definiste en tu clase LinceThemes
      theme: LinceThemes.lightTheme,
      darkTheme: LinceThemes.darkTheme,
      // Conectamos el MaterialApp a nuestra variable de estado
      themeMode: _themeMode, 
      home: const AuthGate(),
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
          // Usamos los colores del tema actual en lugar de colores fijos
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(LinceThemes.pinkStart),
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          return const MainNavScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// Tu clase LinceThemes se mantiene igual (está muy bien definida)
class LinceThemes {
  // Colores base que se mantienen en ambos (Identidad de marca)
  static const Color pinkStart = Color(0xFFFF4D6D);
  static const Color orangeEnd = Color(0xFFFF8A00);
  static const Color matchGreen = Color(0xFF4CAF50);

  // TEMA OSCURO (El original)
  static final darkTheme = ThemeData(
    colorScheme: ColorScheme.dark(
      primary: pinkStart,
      secondary: orangeEnd,
      tertiary: matchGreen,
    ),
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E), //para _surface y card.
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Color(0xFFAAAAAA)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: Color(0xFF252525),
      hintStyle: TextStyle(color: Color( 0xFF555555)),
      iconColor: Color.fromARGB(255, 255, 255, 255),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.white10),
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
    iconTheme: const IconThemeData(color: Colors.black), // Iconos negros para el tema oscuro contrasta con el fondo oscuro
    primaryIconTheme: const IconThemeData(color: Colors.blue),
  );

  // TEMA CLARO (El nuevo)
  static final lightTheme = ThemeData(
    colorScheme: ColorScheme.light(
      primary: pinkStart,
      secondary: orangeEnd,
      tertiary: matchGreen,
    ),
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5), // Blanco hueso
    cardColor: Colors.white,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF121212)), // Texto casi negro
      bodyMedium: TextStyle(color: Color.fromARGB(255, 73, 73, 73)), // Gris suave
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      iconTheme: IconThemeData(color: Color(0xFF121212)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: Color(0xFFF5F5F5),
      hintStyle: TextStyle(color: Color( 0x00555555)),
      iconColor: Color(0xFF121212),
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
    iconTheme: const IconThemeData(color: Color(0xFFE0E0E0)), // Iconos en gris claro para el tema claro contrasta con el fondo blanco
    primaryIconTheme: const IconThemeData(color: Color.fromARGB(255, 0, 140, 255)),
    /*iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all(Colors.white),
        shadowColor: MaterialStateProperty.all(pinkStart.withValues(alpha: 0.2)),
      ),
    ),*/
  );
}

/* primer intento de tema dinámico, pero no funciona bien con el sistema del celular
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
      home: const AuthGate(),
      */*/