import 'package:flutter/material.dart';
import '../ui/screens/auth_check.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/initial_screen.dart';
import '../ui/screens/cadastro_screen.dart';
// Note que não precisamos importar as homes individuais aqui, 
// pois o AuthCheck já faz isso lá dentro dele!

class DefendePraMimApp extends StatelessWidget {
  const DefendePraMimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DefendePraMim',
      
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

      // 🚩 O AuthCheck decide qual tela mostrar primeiro
      home: const AuthCheck(), 

      // 🚩 MAPA DE ROTAS
      routes: {
        '/inicio': (context) => const InitialScreen(),
        '/login': (context) => const LoginScreen(),
        '/cadastro': (context) => const TelaCadastro(),
        
        // 🚀 A GRANDE MUDANÇA: A rota /home agora aponta para o Cérebro do App!
        '/home': (context) => const AuthCheck(), 
      },
    ); 
  }
}