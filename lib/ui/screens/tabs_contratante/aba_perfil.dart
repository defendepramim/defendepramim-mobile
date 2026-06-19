import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart'; // 🟢 Pacote de permissões

class AbaPerfilContratante extends StatefulWidget {
  const AbaPerfilContratante({super.key});

  @override
  State<AbaPerfilContratante> createState() => _AbaPerfilContratanteState();
}

class _AbaPerfilContratanteState extends State<AbaPerfilContratante> {
  bool _carregandoFoto = false;

  static const primaryColor = Color(0xFF00E676);
  static const surfaceColor = Color(0xFF121212);
  static const bgAvatar = Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
  }

  // ✨ BUSCA ORGANIZADOS E CANCELADOS
  // ✨ BUSCA ORGANIZADOS E CANCELADOS (Matemática Blindada)
  Stream<Map<String, int>> _getEstatisticasContratante(String? uid) {
    if (uid == null) return Stream.value({'organizados': 0, 'cancelados': 0});

    return FirebaseFirestore.instance
        .collection('jogos')
        .where('idContratante', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      int organizados = 0;
      int cancelados = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase().trim();
        final canceladoPor = (data['canceladoPor'] ?? '').toString().toLowerCase().trim();

        // 🔴 SOMA CANCELAMENTO: Apenas se o status for cancelado E a culpa for do contratante
        if (status == 'cancelado' && canceladoPor == 'contratante') {
          cancelados++;
        } 
        // 🟢 SOMA SUCESSO: Apenas jogos que realmente aconteceram e foram pagos
        else if (status == 'finalizado') {
          organizados++;
        }
        
        // 👻 BURACO NEGRO: Jogos 'abertos' (futuros ou expirados sem goleiro), 
        // 'fechados' (ainda não jogados) ou cancelados por terceiros são sumariamente ignorados na matemática!
      }

      return {
        'organizados': organizados,
        'cancelados': cancelados,
      };
    });
  }
  
  // 📸 1. MENU DE OPÇÕES (Galeria ou Câmera)
  void _abrirMenuDeFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E), // Fundo padrão do app
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("Atualizar Foto", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: primaryColor),
              title: const Text("Escolher da Galeria", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(ImageSource.gallery); // Chama a função passando Galeria
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: primaryColor),
              title: const Text("Tirar Foto com a Câmera", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(ImageSource.camera); // Chama a função passando Câmera
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ☁️ 2. FUNÇÃO DE UPLOAD ATUALIZADA (Agora aceita a fonte da imagem)
  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    // Usa a fonte selecionada no menu (Câmera ou Galeria)
    final XFile? image = await picker.pickImage(source: source, imageQuality: 50);

    if (image == null) return;
    setState(() => _carregandoFoto = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // ⚠️ ATENÇÃO: Mude 'perfil_contratantes' para 'perfil_goleiros' quando for no arquivo do Goleiro!
      final storageRef = FirebaseStorage.instance.ref().child('perfil_contratantes').child('${user.uid}.jpg');
      await storageRef.putFile(File(image.path));
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).update({'fotoUrl': downloadUrl});

      if (mounted) _showSnackBarOriginal("Foto atualizada com sucesso!", Colors.green);
    } catch (e) {
      debugPrint("Erro no upload: $e");
      if (mounted) _showSnackBarOriginal("Erro ao atualizar foto.", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _carregandoFoto = false);
    }
  }

  // 🔍 3. ZOOM NA FOTO
  void _verFotoMaximizada(String url) {
    if (url.isEmpty) return; // Se não tiver foto, não faz nada
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10), // Margemzinha pra não colar na tela toda
        child: Stack(
          alignment: Alignment.center,
          children: [
            // InteractiveViewer permite fazer o zoom com os dedos (efeito pinça!)
            InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            // Botãozinho de fechar no topo
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(128), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          final nome = dados?['nome'] ?? "Contratante";
          final email = user?.email ?? "E-mail não cadastrado";
          final fotoUrl = dados?['fotoUrl'] ?? "";

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
                                const Icon(Icons.verified_user_rounded, color: primaryColor, size: 16),
                                const SizedBox(width: 4),
                                const Text("Perfil Contratante", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
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
                  StreamBuilder<Map<String, int>>(
                    stream: _getEstatisticasContratante(user?.uid),
                    builder: (context, statsSnapshot) {
                      final stats = statsSnapshot.data ?? {'organizados': 0, 'cancelados': 0};
                      return Row(
                        children: [
                          Expanded(child: _buildMiniStat("ORGANIZADOS", stats['organizados'].toString(), primaryColor, Icons.sports_soccer)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildMiniStat("CANCELADOS", stats['cancelados'].toString(), Colors.redAccent, Icons.block_flipped)),
                        ],
                      );
                    }
                  ),
                  const SizedBox(height: 25),
                  _buildSecaoCard("DADOS DA CONTA", [
                    _itemSimples(Icons.alternate_email_rounded, "E-mail", email),
                    _divider(),
                    _itemSimples(FontAwesomeIcons.whatsapp, "WhatsApp", dados?['telefone'] ?? "Não informado"),
                    _divider(),
                    _itemSimples(Icons.badge_outlined, "CPF", dados?['cpf'] ?? "Não informado"),
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
        // 🟢 Clicar na foto em si abre o Zoom!
        GestureDetector(
          onTap: () => _verFotoMaximizada(url),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor.withAlpha(76), width: 2)), 
            child: CircleAvatar(
              radius: 32,
              backgroundColor: bgAvatar,
              backgroundImage: url != "" ? NetworkImage(url) : null,
              child: url == "" ? Text(nome[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: primaryColor, fontWeight: FontWeight.bold)) : null,
            ),
          ),
        ),
        
        if (_carregandoFoto) const CircleAvatar(radius: 32, backgroundColor: Colors.black54, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2)),
        
        // 🟢 Clicar no botão da câmera abre o novo Menu Inteligente!
        Positioned(
          bottom: -2,
          right: -2,
          child: GestureDetector(
            onTap: _abrirMenuDeFoto, // ⬅️ Agora chama nosso menu bonitão
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

  Widget _buildMiniStat(String label, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
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