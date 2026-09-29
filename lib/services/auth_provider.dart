import 'package:flutter/foundation.dart'; // 🟢 Adicionado para usar o debugPrint
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/usuario_model.dart';

// 🟢 PEÇA 1: Vigia se o usuário está logado no Firebase (E-mail/Senha)
final authStateProvider = StreamProvider((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userProfileProvider = StreamProvider((ref) {
  final authAsync = ref.watch(authStateProvider);
  final user = authAsync.value;

  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('usuarios')
      .doc(user.uid)
      .snapshots()
      .map((snapshot) {
        // Se o snapshot vier vazio mas o Firebase diz que o documento existe no servidor
        if (!snapshot.exists) {
          debugPrint("⚠️ Alerta: Firestore retornou snapshot vazio para ${user.uid}");
          return null; 
        }
        
        final data = snapshot.data();
        if (data == null) return null;

        debugPrint("✅ Perfil validado: ${data['tipoPerfil']}");
        return UsuarioModel.fromMap(data, snapshot.id);
      });
});