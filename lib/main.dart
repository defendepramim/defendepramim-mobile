import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    // MUDANÇA: 'edgeToEdge' é muito mais fluido para o teclado do que 'immersiveSticky'
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  ]);

  // Mantemos o estilo premium, mas permitindo que o sistema gerencie o teclado melhor
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  try {
    await Firebase.initializeApp();
    debugPrint("Firebase OK!");
  } catch (e) {
    debugPrint("Erro Firebase: $e");
  }

  runApp(
    const ProviderScope(
      child: GlobalKeyboardDismiss(child: DefendePraMimApp()),
    ),
  );
}

/// 🔑 WRAPPER CIRÚRGICO: Fecha o teclado ao tocar em qualquer lugar vazio do app
class GlobalKeyboardDismiss extends StatelessWidget {
  final Widget child;
  const GlobalKeyboardDismiss({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Encontra o foco atual e o remove, fechando o teclado com suavidade
        FocusScopeNode currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: child,
    );
  }
}