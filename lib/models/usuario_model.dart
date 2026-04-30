class UsuarioModel {
  final String uid;
  final String nome;
  final String email;
  final String tipoPerfil; // 'goleiro' ou 'contratante'

  UsuarioModel({
    required this.uid,
    required this.nome,
    required this.email,
    required this.tipoPerfil,
  });

  // Transforma o JSON do Firebase em um Objeto C# / Dart
  factory UsuarioModel.fromMap(Map<String, dynamic> map, String id) {
    return UsuarioModel(
      uid: id,
      nome: map['nome'] ?? '',
      email: map['email'] ?? '',
      tipoPerfil: map['tipoPerfil'] ?? 'contratante', // Default por segurança
    );
  }
}