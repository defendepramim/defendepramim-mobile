import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AbaPerfilGoleiro extends StatefulWidget {
  const AbaPerfilGoleiro({super.key});

  @override
  State<AbaPerfilGoleiro> createState() => _AbaPerfilGoleiroState();
}

class _AbaPerfilGoleiroState extends State<AbaPerfilGoleiro> {
  bool _carregandoFoto = false;

  static const primaryColor = Color(0xFF00E676);
  static const surfaceColor = Color(0xFF121212);
  static const bgAvatar = Color(0xFF1E1E1E);

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (image == null) return;
    setState(() => _carregandoFoto = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final storageRef = FirebaseStorage.instance.ref().child('perfil_goleiros').child('${user.uid}.jpg');
      await storageRef.putFile(File(image.path));
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).update({'fotoUrl': downloadUrl});

      if (mounted) _showSnackBarOriginal("Foto atualizada!", Colors.green);
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
        stream: FirebaseFirestore.instance.collection('usuarios').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final dados = snapshot.data?.data() as Map<String, dynamic>?;
          final nome = dados?['nome'] ?? "Goleiro";
          final email = user?.email ?? "E-mail";
          final fotoUrl = dados?['fotoUrl'] ?? "";
          final totalGanhos = (dados?['totalGanhos'] ?? 0.0).toDouble();
          final atuadas = dados?['atuadas'] ?? 0;
          final faltas = dados?['faltas'] ?? 0;

          int soma = dados?['somaAvaliacoes'] ?? 0;
          int total = dados?['totalAvaliacoes'] ?? 0;
          double media = total > 0 ? soma / total : 0.0;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  
                  // 🟢 TOPO UBER: Compacto e direto ao ponto
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nome,
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  total > 0 ? media.toStringAsFixed(1) : "Novo Goleiro",
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text("$total avaliações", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      _buildAvatarHorizontal(fotoUrl, nome),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // 🟢 OS CARDS BONITOS VOLTARAM!
                  _buildDashboardGoleiro(totalGanhos, atuadas, faltas),

                  const SizedBox(height: 25),

                  // DADOS DA CONTA (Achatados visualmente)
                  _buildSecaoCard("DADOS DA CONTA", [
                    _itemSimples(Icons.alternate_email_rounded, "E-mail", email),
                    _divider(),
                    _itemSimples(FontAwesomeIcons.whatsapp, "WhatsApp", dados?['telefone'] ?? "---"),
                    _divider(),
                    _itemSimples(Icons.badge_outlined, "CPF", dados?['cpf'] ?? "---"),
                  ]),

                  const SizedBox(height: 15),

                  _buildSecaoCard("CONFIGURAÇÕES", [
                    _itemMenuClicavel(Icons.lock_reset_rounded, "Alterar Senha", Colors.amber, () {
                      if(user?.email != null) {
                        FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                        _showSnackBarOriginal("Link enviado para seu e-mail!", Colors.green);
                      }
                    }),
                    _divider(),
                    _itemMenuClicavel(Icons.logout_rounded, "Sair da Conta", Colors.redAccent, () {
                      FirebaseAuth.instance.signOut();
                    }),
                  ]),
                  
                  const SizedBox(height: 30),
                  const Center(child: Text("Defende Pra Mim v1.0.0", style: TextStyle(color: Colors.white10, fontSize: 10))),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildAvatarHorizontal(String url, String nome) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor.withOpacity(0.3), width: 2)),
          child: CircleAvatar(
            radius: 32,
            backgroundColor: bgAvatar,
            backgroundImage: url != "" ? NetworkImage(url) : null,
            child: url == "" ? Text(nome[0], style: const TextStyle(fontSize: 24, color: primaryColor, fontWeight: FontWeight.bold)) : null,
          ),
        ),
        if (_carregandoFoto) const CircleAvatar(radius: 32, backgroundColor: Colors.black54, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2)),
        Positioned(
          bottom: -2,
          right: -2,
          child: GestureDetector(
            onTap: _pickAndUploadImage,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, size: 12, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardGoleiro(double ganhos, int partidas, int faltas) {
    return Column(
      children: [
        // Card de Ganhos em destaque (Largo e imponente)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TOTAL GANHO", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("R\$ ${ganhos.toStringAsFixed(2)}", style: const TextStyle(color: primaryColor, fontSize: 28, fontWeight: FontWeight.w900)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.monetization_on_rounded, color: primaryColor, size: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Mini cards de suporte bonitões
        Row(
          children: [
            Expanded(child: _buildMiniStat("PARTIDAS", partidas.toString(), Colors.blueAccent, Icons.sports_soccer)),
            const SizedBox(width: 10),
            Expanded(child: _buildMiniStat("FALTAS", faltas.toString(), Colors.redAccent, Icons.warning_amber_rounded)),
          ],
        ),
      ],
    );
  }

Widget _buildMiniStat(String label, String valor, Color cor, IconData icone) {
    return Container(
      // Diminuímos um pouco o padding vertical
      padding: const EdgeInsets.symmetric(vertical: 12), 
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // Ícone e Número agora dividem a mesma linha
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, color: cor.withOpacity(0.7), size: 18),
              const SizedBox(width: 8),
              Text(valor, style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSecaoCard(String titulo, List<Widget> filhos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(titulo, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(children: filhos),
        ),
      ],
    );
  }

Widget _itemSimples(dynamic icon, String label, String info) {
    return ListTile(
      // Tiramos o "visualDensity" negativo que estava esmagando os itens
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: icon is IconData ? Icon(icon, color: Colors.white24, size: 20) : FaIcon(icon as FaIconData, color: Colors.white24, size: 18),
      title: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      subtitle: Text(info, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }

  Widget _itemMenuClicavel(IconData icon, String title, Color cor, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: cor.withOpacity(0.8), size: 20),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white10, size: 18),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Colors.white10, indent: 50);

  void _showSnackBarOriginal(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor, behavior: SnackBarBehavior.floating),
    );
  }
}