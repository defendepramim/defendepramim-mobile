import 'package:flutter/material.dart';
import '../ui/screens/auth_check.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/initial_screen.dart';
import '../ui/screens/cadastro_screen.dart';
// Se tiver a tela Home real, importe ela aqui:
// import '../ui/screens/home_screen.dart'; 

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

      // 🚩 O AuthCheck decide qual tela mostrar primeiro (Login ou Home)
      home: const AuthCheck(), 

      // 🚩 MAPA DE ROTAS - O Navigator precisa disso para não crashar
      routes: {
        '/inicio': (context) => const InitialScreen(),
        '/login': (context) => const LoginScreen(),
        '/cadastro': (context) => const TelaCadastro(),
        
        // ESSA LINHA É OBRIGATÓRIA se você usa pushNamed('/home')
        '/home': (context) => const Scaffold(
          body: Center(child: Text("Bem-vindo ao DefendePraMim!")),
        ), 
        // 👆 Se você tiver uma classe como 'HomeScreen()', coloque-a aqui no lugar do Scaffold.
      },
    ); 
  }
}