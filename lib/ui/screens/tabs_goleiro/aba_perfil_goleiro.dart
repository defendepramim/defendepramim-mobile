import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart'; // 🟢 Pacote de permissões

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

  @override
  void initState() {
    super.initState();
  }

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

  // ✏️ NOVA FUNÇÃO: EDITAR O NOME DO GOLEIRO
  Future<void> _editarNome(String nomeAtual) async {
    final controller = TextEditingController(text: nomeAtual);
    final formKey = GlobalKey<FormState>();
    bool salvando = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: primaryColor, width: 0.5),
              ),
              title: const Text("Como prefere ser chamado?", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: "Seu Nome Completo",
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryColor)),
                  ),
                  validator: (v) => v!.trim().isEmpty ? "O nome não pode ser vazio" : null,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: salvando ? null : () => Navigator.pop(context),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: salvando ? null : () async {
                    if (!formKey.currentState!.validate()) return;
                    setDialogState(() => salvando = true);
                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).update({
                          'nome': controller.text.trim(),
                          'nomeBusca': controller.text.trim().toLowerCase(),
                        });
                        if (mounted) {
                          Navigator.pop(context);
                          _showSnackBarOriginal("Nome atualizado com sucesso!", Colors.green);
                        }
                      }
                    } catch (e) {
                      setDialogState(() => salvando = false);
                      _showSnackBarOriginal("Erro ao atualizar nome.", Colors.redAccent);
                    }
                  },
                  child: salvando 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text("SALVAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  // 🟢 NOVA FUNÇÃO INTELIGENTE DE TROCA DE SENHA
  Future<void> _solicitarTrocaDeSenha(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    // Checa se é usuário do Google
    bool isGoogle = user.providerData.any((p) => p.providerId == 'google.com');

    if (isGoogle) {
      _showSnackBarOriginal("Sua conta é vinculada ao Google. A senha deve ser alterada diretamente na sua conta Google.", Colors.orangeAccent);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: Color(0xFF00E676)),
                SizedBox(width: 10),
                Text("E-mail Enviado!", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              "Enviamos um link de redefinição para o seu e-mail. Verifique sua caixa de entrada (e o spam) para criar uma nova senha.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ENTENDIDO", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnackBarOriginal("Erro ao enviar o e-mail. Tente novamente mais tarde.", Colors.redAccent);
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    nome,
                                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _editarNome(nome),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: primaryColor.withAlpha(26), borderRadius: BorderRadius.circular(6)), // 🧹 Opacity Limpo
                                    child: const Icon(Icons.edit_rounded, color: primaryColor, size: 18),
                                  ),
                                ),
                              ],
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
                  _buildDashboardGoleiro(totalGanhos, atuadas, faltas),
                  const SizedBox(height: 25),
                  _buildSecaoCard("DADOS DA CONTA", [
                    _itemSimples(Icons.alternate_email_rounded, "E-mail", email),
                    _divider(),
                    _itemSimples(FontAwesomeIcons.whatsapp, "WhatsApp", dados?['telefone'] ?? "---"),
                    _divider(),
                    _itemSimples(Icons.badge_outlined, "CPF", dados?['cpf'] ?? "---"),
                  ]),
                  const SizedBox(height: 15),
                  _buildSecaoCard("CONFIGURAÇÕES", [
                    // 🟢 AQUI CHAMAMOS A FUNÇÃO MÁGICA
                    _itemMenuClicavel(Icons.lock_reset_rounded, "Alterar Senha", Colors.amber, () {
                      _solicitarTrocaDeSenha(context);
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

  Widget _buildAvatarHorizontal(String url, String nome) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor.withAlpha(76), width: 2)), // 🧹 Opacity Limpo
          child: CircleAvatar(
            radius: 32,
            backgroundColor: bgAvatar,
            backgroundImage: url != "" ? NetworkImage(url) : null,
            child: url == "" ? Text(nome[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: primaryColor, fontWeight: FontWeight.bold)) : null,
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withAlpha(13))), // 🧹 Opacity Limpo
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
                decoration: BoxDecoration(color: primaryColor.withAlpha(26), shape: BoxShape.circle), // 🧹 Opacity Limpo
                child: const Icon(Icons.monetization_on_rounded, color: primaryColor, size: 28),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 12), 
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white.withAlpha(13))), // 🧹 Opacity Limpo
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, color: cor.withAlpha(179), size: 18), // 🧹 Opacity Limpo
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
          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withAlpha(13))), // 🧹 Opacity Limpo
          child: Column(children: filhos),
        ),
      ],
    );
  }

  Widget _itemSimples(dynamic icon, String label, String info) {
    return ListTile(
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
      leading: Icon(icon, color: cor.withAlpha(204), size: 20), // 🧹 Opacity Limpo
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white10, size: 18),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Colors.white10, indent: 50);

  void _showSnackBarOriginal(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: cor, behavior: SnackBarBehavior.floating));
  }
}