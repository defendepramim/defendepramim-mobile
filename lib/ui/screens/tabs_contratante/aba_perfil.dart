import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart'; // 🟢 INJETADO PARA O PIX

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

  // --- 🚨 FLUXO DE EXCLUSÃO DE CONTA BLINDADO ---

  Future<void> _verificarPendenciasEExcluir(BuildContext context, String uid, double saldo) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
    );

    try {
      final queryJogos = await FirebaseFirestore.instance
          .collection('jogos')
          .where('idContratante', isEqualTo: uid)
          .where('status', whereIn: ['aberto', 'fechado'])
          .get();

      if (!context.mounted) return;
      Navigator.pop(context); 

      final agora = DateTime.now();
      int pendenciasReais = 0;

      for (var doc in queryJogos.docs) {
        final data = doc.data();
        final status = data['status'];
        final Timestamp? ts = data['dataHora'];
        final DateTime dataJogo = ts?.toDate() ?? agora;

        if (status == 'fechado') {
          pendenciasReais++;
        } 
        else if (status == 'aberto' && dataJogo.isAfter(agora)) {
          pendenciasReais++;
        }
      }

      if (pendenciasReais > 0) {
        _mostrarAlertaBloqueio(context, "Você possui $pendenciasReais partida(s) em aberto ou agendada(s). Por favor, cancele os jogos ou aguarde a finalização antes de excluir sua conta.");
        return;
      }

      _abrirModalExclusao(context, saldo);

    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showSnackBarOriginal("Erro ao verificar pendências.", Colors.redAccent);
    }
  }
  
  void _mostrarAlertaBloqueio(BuildContext context, String mensagem) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 2)),
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text("Ação Bloqueada", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 14)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ENTENDIDO", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _abrirModalExclusao(BuildContext context, double saldo) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 1)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text("Excluir Conta?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 14),
            children: [
              const TextSpan(text: "Esta ação é irreversível. Todos os seus dados, histórico de partidas e foto de perfil serão apagados permanentemente do nosso sistema.\n\n"),
              if (saldo > 0) ...[
                const TextSpan(text: "⚠️ ATENÇÃO: ", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                const TextSpan(text: "Você possui um saldo na carteira de "),
                TextSpan(text: "R\$ ${saldo.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const TextSpan(text: ". Ao excluir a conta, esse valor será "),
                const TextSpan(text: "PERDIDO PARA SEMPRE. ", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                const TextSpan(text: "Recomendamos que você saque antes de prosseguir."),
              ] else ...[
                const TextSpan(text: "Atenção: Certifique-se de não ter pendências antes de prosseguir."),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(dialogContext);
              _processarExclusao(context); 
            },
            child: const Text("SIM, EXCLUIR", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processarExclusao(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
    );

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser != null) {
        
        // 🚀 PASSO ÚNICO: Tenta deletar a conta no Firebase Auth.
        // Se der certo, o nosso `index.js` vai limpar o Firestore na nuvem!
        try {
          await currentUser.delete();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            navigator.pop(); // Fecha o loading
            
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.security, color: Colors.orangeAccent),
                    SizedBox(width: 10),
                    Text("Reautenticação Necessária", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: const Text(
                  "Por motivos de segurança, você precisa ter feito login recentemente para excluir sua conta.\n\nSua conta foi desconectada. Por favor, faça login novamente e solicite a exclusão.",
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await FirebaseAuth.instance.signOut();
                      try { 
                        await GoogleSignIn().disconnect(); 
                        await GoogleSignIn().signOut(); 
                      } catch (_) {}
                      navigator.pushNamedAndRemoveUntil('/', (route) => false);
                    },
                    child: const Text("ENTENDIDO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
            return; // 🛑 Interrompe com segurança. Nenhum dado fantasma foi gerado!
          } else {
            rethrow; 
          }
        }

        // 🚀 PASSO 2: Limpeza total das credenciais locais no celular
        try { 
          await GoogleSignIn().disconnect();
          await GoogleSignIn().signOut(); 
        } catch (_) {}
        await FirebaseAuth.instance.signOut();

        if (navigator.mounted) {
          navigator.pushNamedAndRemoveUntil('/', (route) => false);
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text("Sua conta e dados foram excluídos com sucesso."), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception("Sessão expirada ou usuário não encontrado.");
      }
    } catch (e) {
      if (navigator.mounted) navigator.pop(); 
      scaffoldMessenger.showSnackBar(SnackBar(content: Text("Erro ao excluir conta: $e"), backgroundColor: Colors.redAccent));
    }
  }
  
  // --- 📸 FOTO DE PERFIL E EDIÇÃO ---
  void _abrirMenuDeFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E), 
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Atualizar Foto", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: primaryColor),
              title: const Text("Escolher da Galeria", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(ImageSource.gallery); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: primaryColor),
              title: const Text("Tirar Foto com a Câmera", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadImage(ImageSource.camera); 
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 50);

    if (image == null) return;
    setState(() => _carregandoFoto = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

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

  void _verFotoMaximizada(String url) {
    if (url.isEmpty) return; 
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10), 
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
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

  Future<void> _solicitarTrocaDeSenha(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

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

  // 🟢 --- LÓGICA DO PIX MIGRADAS PARA CÁ ---
  void _abrirModalPix(String chaveAtual, String tipoAtual, Map<String, dynamic> dadosUsuario) {
    final validos = ['cpf', 'telefone', 'email', 'aleatoria'];
    String tipoLimpo = tipoAtual.toLowerCase().trim();
    String tipoSelecionado = validos.contains(tipoLimpo) ? tipoLimpo : 'cpf';

    final TextEditingController pixController = TextEditingController();
    final TextEditingController confirmarController = TextEditingController();
    
    String? erroMensagem;
    bool processando = false;

    var cpfMask = MaskTextInputFormatter(mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
    var telMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
    MaskTextInputFormatter? currentMask;

    String formatCpf(String c) {
      String limpo = c.replaceAll(RegExp(r'[^0-9]'), '');
      if (limpo.length == 11) return "${limpo.substring(0,3)}.${limpo.substring(3,6)}.${limpo.substring(6,9)}-${limpo.substring(9)}";
      return c;
    }

    String formatTel(String t) {
      String limpo = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (limpo.length == 11) return "(${limpo.substring(0,2)}) ${limpo.substring(2,7)}-${limpo.substring(7)}";
      if (limpo.length == 10) return "(${limpo.substring(0,2)}) ${limpo.substring(2,6)}-${limpo.substring(6)}";
      return t;
    }

    void aplicarLogicaInicial() {
      if (tipoSelecionado == 'cpf') {
        currentMask = cpfMask;
        pixController.text = chaveAtual.isNotEmpty && tipoLimpo == 'cpf' ? chaveAtual : formatCpf(dadosUsuario['cpf']?.toString() ?? '');
      } else if (tipoSelecionado == 'telefone') {
        currentMask = telMask;
        pixController.text = chaveAtual.isNotEmpty && tipoLimpo == 'telefone' ? chaveAtual : formatTel(dadosUsuario['telefone']?.toString() ?? '');
      } else if (tipoSelecionado == 'email') {
        currentMask = null;
        pixController.text = chaveAtual.isNotEmpty && tipoLimpo == 'email' ? chaveAtual : dadosUsuario['email']?.toString() ?? '';
      } else {
        currentMask = null;
        pixController.text = chaveAtual.isNotEmpty && tipoLimpo == tipoSelecionado ? chaveAtual : '';
      }
    }

    aplicarLogicaInicial();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            bool precisaConfirmacao = tipoSelecionado == 'aleatoria';

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Cadastrar Chave PIX", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx))
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("Precisamos de uma chave para processar o seu saque e estornos.", style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 20),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: tipoSelecionado,
                        dropdownColor: const Color(0xFF2A2A2A),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        icon: const Icon(Icons.arrow_drop_down, color: primaryColor),
                        items: const [
                          DropdownMenuItem(value: 'cpf', child: Text("CPF")),
                          DropdownMenuItem(value: 'telefone', child: Text("Telefone / Celular")),
                          DropdownMenuItem(value: 'email', child: Text("E-mail")),
                          DropdownMenuItem(value: 'aleatoria', child: Text("Chave Aleatória")),
                        ],
                        onChanged: (val) {
                          setStateModal(() {
                            tipoSelecionado = val!;
                            erroMensagem = null; 
                            if (tipoSelecionado == 'cpf') {
                              currentMask = cpfMask;
                              pixController.text = formatCpf(dadosUsuario['cpf']?.toString() ?? '');
                            } else if (tipoSelecionado == 'telefone') {
                              currentMask = telMask;
                              pixController.text = formatTel(dadosUsuario['telefone']?.toString() ?? '');
                            } else if (tipoSelecionado == 'email') {
                              currentMask = null;
                              pixController.text = dadosUsuario['email']?.toString() ?? '';
                            } else {
                              currentMask = null;
                              pixController.clear();
                            }
                            confirmarController.clear();
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: pixController,
                    style: const TextStyle(color: Colors.white),
                    inputFormatters: currentMask != null ? [currentMask!] : [],
                    keyboardType: (tipoSelecionado == 'cpf' || tipoSelecionado == 'telefone') ? TextInputType.number : TextInputType.text,
                    onChanged: (_) => setStateModal(() => erroMensagem = null),
                    decoration: InputDecoration(
                      labelText: "Sua Chave",
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.pix, color: Color(0xFF00E676)),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),

                  if (precisaConfirmacao) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmarController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setStateModal(() => erroMensagem = null),
                      decoration: InputDecoration(
                        labelText: "Confirme a Chave",
                        labelStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.check_circle_outline, color: Colors.orangeAccent),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  if (erroMensagem != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withAlpha(26),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withAlpha(51)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(erroMensagem!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ]),
                    ),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: processando ? null : () async {
                        String chaveFinal = pixController.text.trim();
                        String chaveConfirmacao = confirmarController.text.trim();
                        
                        if (chaveFinal.isEmpty) {
                          setStateModal(() => erroMensagem = "A chave PIX não pode ser vazia.");
                          return;
                        }

                        if (precisaConfirmacao) {
                          if (chaveConfirmacao.isEmpty) {
                             setStateModal(() => erroMensagem = "Por favor, confirme a chave aleatória.");
                             return;
                          }
                          if (chaveFinal != chaveConfirmacao) {
                            setStateModal(() => erroMensagem = "As chaves não coincidem! Verifique a digitação.");
                            return; 
                          }
                        }
                        
                        FocusScope.of(context).unfocus();
                        setStateModal(() => processando = true);
                        
                        try {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null) {
                            await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
                              'chavePix': chaveFinal,
                              'tipoPix': tipoSelecionado,
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnackBarOriginal("Chave PIX atualizada com sucesso!", Colors.green);
                          }
                        } catch (e) {
                          setStateModal(() {
                            erroMensagem = "Erro ao atualizar chave PIX.";
                            processando = false;
                          });
                        }
                      },
                      child: processando 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text("SALVAR CHAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

          final dados = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final nome = dados['nome'] ?? "Contratante";
          final email = user?.email ?? "E-mail";
          final fotoUrl = dados['fotoUrl'] ?? "";
          
          final chavePix = dados['chavePix']?.toString() ?? "";
          final tipoPix = dados['tipoPix']?.toString() ?? "";
          
          // Preferir centavos (oficial); fallback legado em reais
          final int totalGastosCentavos =
              (dados['totalGastosCentavos'] as num?)?.round() ?? 0;
          final double totalGastos = totalGastosCentavos > 0
              ? totalGastosCentavos / 100.0
              : (dados['totalGastos'] as num?)?.toDouble() ?? 0.0;
          final partidasOrganizadas = dados['partidasOrganizadas'] ?? 0;
          final cancelamentos = dados['cancelamentos'] ?? 0;

          // Avaliações RECEBIDAS dos goleiros — não as que o contratante deu aos goleiros
          final double soma = (dados['somaAvaliacoes'] as num?)?.toDouble() ??
              (dados['somaNotasAvaliacoes'] as num?)?.toDouble() ??
              0.0;
          final int total = (dados['totalAvaliacoes'] as num?)?.toInt() ?? 0;
          final double media = total > 0 ? soma / total : 0.0;

          final saldoAviso = (dados['saldo'] ?? 0.0).toDouble() - (dados['multasPendentes'] ?? 0.0).toDouble();

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
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
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _editarNome(nome),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: primaryColor.withAlpha(26), borderRadius: BorderRadius.circular(6)), 
                                    child: const Icon(Icons.edit_rounded, color: primaryColor, size: 16),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  total > 0 ? media.toStringAsFixed(1) : "Novo Contratante",
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 8),
                                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text(total > 0 ? "$total avaliações" : "sem avaliações ainda", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildAvatarHorizontal(fotoUrl, nome),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDashboardContratante(totalGastos, partidasOrganizadas, cancelamentos),
                  const SizedBox(height: 16),
                  
                  // 🟢 O CARD MONTADO NO LUGAR CERTO!
                  _buildSecaoCard("DADOS DA CONTA", [
                    _itemSimples(Icons.alternate_email_rounded, "E-mail", email),
                    _divider(),
                    _itemSimples(FontAwesomeIcons.whatsapp, "WhatsApp", _mascararTelefone(dados['telefone']?.toString() ?? "")),
                    _divider(),
                    _itemSimples(Icons.badge_outlined, "CPF", _mascararCPF(dados['cpf']?.toString() ?? "")),
                    _divider(),
                    // 🟢 PIX AGORA É CLICÁVEL!
                    _itemMenuClicavel(
                      Icons.pix, 
                      chavePix.isNotEmpty ? "${tipoPix.toUpperCase()} • ${_mascararChavePix(chavePix)}" : "Cadastrar Chave PIX", 
                      chavePix.isNotEmpty ? Colors.white : Colors.orangeAccent, 
                      () => _abrirModalPix(chavePix, tipoPix, dados)
                    ),
                  ]),
                  
                  const SizedBox(height: 16),
                  
                  _buildSecaoCard("CONFIGURAÇÕES", [
                    _itemMenuClicavel(Icons.lock_reset_rounded, "Alterar Senha", Colors.amber, () {
                      _solicitarTrocaDeSenha(context);
                    }),
                    _divider(),
                    _itemMenuClicavel(Icons.logout_rounded, "Sair da Conta", Colors.orangeAccent, () {
                      FirebaseAuth.instance.signOut();
                    }),
                  ]),
                  
                  const SizedBox(height: 120),
                  
                  _buildSecaoCard("EXCLUIR A CONTA", [
                    _itemMenuClicavel(Icons.delete_forever_outlined, "Excluir Definitivamente a Conta", Colors.redAccent, () {
                      _verificarPendenciasEExcluir(context, user!.uid, saldoAviso);
                    }),
                  ]),
                  
                  const SizedBox(height: 24),
                  const Center(child: Text("Defende Pra Mim v1.0.0", style: TextStyle(color: Colors.white10, fontSize: 10))),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 🟢 FUNÇÕES PARA PROTEGER OS DADOS (LGPD / Privacidade)
  String _mascararCPF(String cpf) {
    String limpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpo.length != 11) return cpf.isNotEmpty ? "*** Confidencial ***" : "---";
    return "***.${limpo.substring(3, 6)}.${limpo.substring(6, 9)}-**";
  }

  String _mascararTelefone(String telefone) {
    String limpo = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpo.length < 10) return telefone.isNotEmpty ? telefone : "---";
    return "(${limpo.substring(0, 2)}) 9****-${limpo.substring(limpo.length - 4)}";
  }

  // 🟢 A FUNÇÃO DO PIX AQUI BEM SEGURA
  String _mascararChavePix(String chave) {
    if (chave.length <= 4) return chave; 
    if (chave.contains('@')) {
      final partes = chave.split('@');
      if (partes[0].length > 3) return '${partes[0].substring(0, 3)}***@${partes[1]}';
      return '***@${partes[1]}';
    }
    return '${chave.substring(0, 3)}***${chave.substring(chave.length - 2)}';
  }

  Widget _buildAvatarHorizontal(String url, String nome) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _verFotoMaximizada(url),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primaryColor.withAlpha(76), width: 2)), 
            child: CircleAvatar(
              radius: 28, 
              backgroundColor: bgAvatar,
              backgroundImage: url != "" ? NetworkImage(url) : null,
              child: url == "" ? Text(nome[0].toUpperCase(), style: const TextStyle(fontSize: 22, color: primaryColor, fontWeight: FontWeight.bold)) : null,
            ),
          ),
        ),
        
        if (_carregandoFoto) const CircleAvatar(radius: 28, backgroundColor: Colors.black54, child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2)),
        
        Positioned(
          bottom: -2,
          right: -2,
          child: GestureDetector(
            onTap: _abrirMenuDeFoto, 
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, size: 12, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildDashboardContratante(double gastos, int partidas, int cancelamentos) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14), 
          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withAlpha(13))), 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TOTAL INVESTIDO", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text("R\$ ${gastos.toStringAsFixed(2)}", style: const TextStyle(color: primaryColor, fontSize: 24, fontWeight: FontWeight.w900)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: primaryColor.withAlpha(26), shape: BoxShape.circle), 
                child: const Icon(Icons.account_balance_wallet_rounded, color: primaryColor, size: 24),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8), 
        Row(
          children: [
            Expanded(child: _buildMiniStat("JOGOS", partidas.toString(), Colors.blueAccent, Icons.sports_soccer)),
            const SizedBox(width: 8), 
            Expanded(child: _buildMiniStat("CANCELADOS", cancelamentos.toString(), Colors.redAccent, Icons.event_busy_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String valor, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10), 
      decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withAlpha(13))), 
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, color: cor.withAlpha(179), size: 16), 
              const SizedBox(width: 6),
              Text(valor, style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSecaoCard(String titulo, List<Widget> filhos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(titulo, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
        Container(
          decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withAlpha(13))), 
          child: Column(children: filhos),
        ),
      ],
    );
  }

  Widget _itemSimples(dynamic icon, String label, String info) {
    return ListTile(
      dense: true, 
      visualDensity: VisualDensity.compact, 
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: icon is FaIconData 
          ? FaIcon(icon, color: Colors.white24, size: 16) 
          : Icon(icon as IconData, color: Colors.white24, size: 18),
      title: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      subtitle: Text(info, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
    );
  }

  Widget _itemMenuClicavel(IconData icon, String title, Color cor, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      dense: true, 
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Icon(icon, color: cor.withAlpha(204), size: 18), 
      title: Text(title, style: TextStyle(color: cor, fontSize: 13, fontWeight: FontWeight.w600)), // Deixei levemente bold para destacar ações
      trailing: const Icon(Icons.chevron_right, color: Colors.white10, size: 16),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Colors.white10, indent: 45);

  void _showSnackBarOriginal(String texto, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), backgroundColor: cor, behavior: SnackBarBehavior.floating));
  }
}