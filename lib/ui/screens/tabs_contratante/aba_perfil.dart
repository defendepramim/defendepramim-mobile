import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AbaPerfilContratante extends StatefulWidget {
  const AbaPerfilContratante({super.key});

  @override
  State<AbaPerfilContratante> createState() => _AbaPerfilContratanteState();
}

class _AbaPerfilContratanteState extends State<AbaPerfilContratante> {
  bool _carregandoFoto = false;

  // Cores padronizadas
  static const primaryColor = Color(0xFF00E676);
  static const surfaceColor = Color(0xFF121212);
  static const bgAvatar = Color(0xFF1E1E1E);

  // --- LÓGICA DE FOTO (IGUAL AO GOLEIRO) ---
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image == null) return;

    setState(() => _carregandoFoto = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Salvando em uma pasta separada para contratantes
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('perfil_contratantes')
          .child('${user.uid}.jpg');

      await storageRef.putFile(File(image.path));
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({'fotoUrl': downloadUrl});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto de perfil atualizada!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Erro no upload: $e");
    } finally {
      if (mounted) setState(() => _carregandoFoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Erro ao carregar dados", style: TextStyle(color: Colors.white)));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final dados = snapshot.data?.data() as Map<String, dynamic>?;
          final nome = (dados?['nome'] ?? "Usuário").toString();
          final email = user?.email ?? "E-mail não cadastrado";
          final fotoUrl = dados?['fotoUrl'] ?? "";

          // Lógica das iniciais
          final partesNome = nome.trim().split(' ');
          final iniciais = partesNome.length > 1 
              ? "${partesNome[0][0]}${partesNome[1][0]}".toUpperCase() 
              : (partesNome[0].isNotEmpty ? partesNome[0][0].toUpperCase() : "?");
          
          final partidasFinalizadas = dados?['partidasFinalizadas'] ?? 0;
          final partidasCanceladas = dados?['qtdCancelamentos'] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              children: [
                /// 👤 HEADER COM FOTO OU INICIAIS
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: primaryColor.withOpacity(0.3), 
                                width: 1.5
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 45,
                              backgroundColor: bgAvatar,
                              backgroundImage: fotoUrl != "" ? NetworkImage(fotoUrl) : null,
                              child: _carregandoFoto 
                                ? const CircularProgressIndicator(color: primaryColor)
                                : (fotoUrl == "" 
                                    ? Text(
                                        iniciais,
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w900,
                                          color: primaryColor,
                                        ),
                                      )
                                    : null),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _carregandoFoto ? null : _pickAndUploadImage,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 22, 
                          fontWeight: FontWeight.w900, 
                          color: Colors.white
                        ),
                      ),
                      Text(
                        email,
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                /// 📊 DASHBOARD DE ESTATÍSTICAS
                Row(
                  children: [
                    _buildStatCard("FINALIZADOS", partidasFinalizadas.toString(), primaryColor),
                    const SizedBox(width: 12),
                    _buildStatCard("CANCELADOS", partidasCanceladas.toString(), Colors.redAccent),
                  ],
                ),

                const SizedBox(height: 24),

                /// 📱 SEÇÃO DE INFORMAÇÕES PESSOAIS
                _buildSecao(
                  "Informações Pessoais",
                  [
                    _itemPerfil(FontAwesomeIcons.whatsapp, "WhatsApp", dados?['telefone'] ?? "Não informado"),
                    const Divider(height: 1, color: Colors.white10, indent: 60),
                    _itemPerfil(Icons.badge_outlined, "CPF", dados?['cpf'] ?? "Não informado"),
                  ],
                ),

                const SizedBox(height: 20),

                /// ⚙️ SEÇÃO DE CONTA E SEGURANÇA
                _buildSecao(
                  "Segurança e Conta",
                  [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.lock_reset_rounded, color: Colors.amber, size: 20),
                      title: const Text("Alterar Senha", style: TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white10, size: 18),
                      onTap: () {
                        if (user?.email != null) {
                          FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                        }
                      },
                    ),
                    const Divider(height: 1, color: Colors.white10, indent: 50),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                      title: const Text("Sair da Conta", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                      onTap: () => FirebaseAuth.instance.signOut(),
                    ),
                  ],
                ),
                
                const SizedBox(height: 30),
                const Text("Defende Pra Mim v1.0.0", style: TextStyle(color: Colors.white10, fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// WIDGETS AUXILIARES
  Widget _buildStatCard(String label, String valor, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Text(valor, style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  Widget _buildSecao(String titulo, List<Widget> itens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            titulo.toUpperCase(), 
            style: const TextStyle(color: primaryColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(children: itens),
        ),
      ],
    );
  }

  Widget _itemPerfil(dynamic icon, String label, String info) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1), 
          shape: BoxShape.circle
        ),
        child: icon is IconData
            ? Icon(icon, color: primaryColor, size: 16)
            : FaIcon(icon as FaIconData, color: primaryColor, size: 16),
      ),
      title: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      subtitle: Text(info, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}