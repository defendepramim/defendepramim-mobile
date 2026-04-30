import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/app.dart'; // Certifique-se que este caminho está certo

void main() async {
  // 1. Acorda o Flutter
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 2. Inicia o Firebase
    await Firebase.initializeApp();
    debugPrint("Firebase OK!");
  } catch (e) {
    debugPrint("Erro Firebase: $e");
  }

  // 3. Roda o SEU APP real agora
  runApp(
    const ProviderScope(
      child: DefendePraMimApp(),
    ),
  );
}