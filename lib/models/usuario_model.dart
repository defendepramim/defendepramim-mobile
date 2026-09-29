class UsuarioModel {
  final String uid;
  final String nome;
  final String email;
  final String tipoPerfil;

  UsuarioModel({
    required this.uid,
    required this.nome,
    required this.email,
    required this.tipoPerfil,
  });

  factory UsuarioModel.fromMap(Map<String, dynamic> map, String id) {
    return UsuarioModel(
      uid: id,
      nome: map['nome'] ?? '',
      email: map['email'] ?? '',
      // 🟢 Normaliza para caixa baixa e evita falhas de rotas
      tipoPerfil: (map['tipoPerfil'] ?? 'contratante').toString().toLowerCase().trim(),
    );
  }
}