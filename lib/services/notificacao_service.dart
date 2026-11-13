import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // 🟢 Traz o debugPrint oficial do Flutter

class NotificacaoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🚀 FUNÇÃO SUPREMA: Cria uma notificação no banco para um usuário específico
  Future<void> enviarNotificacao({
    required String idUsuarioDestino, 
    required String titulo,
    required String mensagem,
    required String tipo, 
  }) async {
    try {
      final docRef = _firestore.collection('notificacoes').doc();
      
      await docRef.set({
        'id': docRef.id,
        'idUsuario': idUsuarioDestino,
        'titulo': titulo,
        'mensagem': mensagem,
        'data': FieldValue.serverTimestamp(),
        'tipo': tipo,
        'lida': false,
      });
    } catch (e) {
      debugPrint("🚨 Erro ao enviar notificação no Firestore: $e");
    }
  }

  /// 🔑 MARCAR COMO LIDA: Atualiza o status no banco quando o usuário clica
  Future<void> marcarComoLida(String idNotificacao) async {
    try {
      await _firestore.collection('notificacoes').doc(idNotificacao).update({
        'lida': true,
      });
    } catch (e) {
      debugPrint("🚨 Erro ao marcar notificação como lida: $e");
    }
  }
}