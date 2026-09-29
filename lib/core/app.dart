import 'package:flutter/material.dart';
// 🟢 1. IMPORT DO PACOTE DE IDIOMAS AQUI:
import 'package:flutter_localizations/flutter_localizations.dart'; 

import '../ui/screens/auth_check.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/initial_screen.dart';
import '../ui/screens/cadastro_screen.dart';
import '../services/push_notification_service.dart';

class DefendePraMimApp extends StatelessWidget {
  const DefendePraMimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'DefendePraMim',
      
      // 🟢 2. CONFIGURAÇÕES DE TRADUÇÃO DO CALENDÁRIO/SISTEMA AQUI:
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Força o Português do Brasil!
      ],

      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF00E676),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF00E676),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E676),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),

      routes: {
        '/': (context) => const AuthCheck(), 
        '/inicio': (context) => const InitialScreen(),
        '/login': (context) => const LoginScreen(),
        '/cadastro': (context) => const TelaCadastro(),
        '/home': (context) => const AuthCheck(), 
      },
    ); 
  }
}