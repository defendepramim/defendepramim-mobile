import 'package:cloud_firestore/cloud_firestore.dart';

class NotificacaoModel {
  final String id;
  final String idUsuario;
  final String titulo;
  final String mensagem;
  final DateTime data;
  final bool lida;
  final String tipo;

  NotificacaoModel({
    required this.id,
    required this.idUsuario,
    required this.titulo,
    required this.mensagem,
    required this.data,
    this.lida = false,
    required this.tipo,
  });

  factory NotificacaoModel.fromFirestore(DocumentSnapshot doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    
    return NotificacaoModel(
      id: doc.id,
      idUsuario: data['idUsuario'] ?? '',
      titulo: data['titulo'] ?? '',
      mensagem: data['mensagem'] ?? '',
      // 🟢 BLINDAGEM: Fallback seguro caso o timestamp do servidor ainda seja null
      data: (data['data'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lida: data['lida'] ?? false,
      tipo: data['tipo'] ?? 'geral',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'idUsuario': idUsuario,
      'titulo': titulo,
      'mensagem': mensagem,
      'data': Timestamp.fromDate(data),
      'lida': lida,
      'tipo': tipo,
    };
  }
}