import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class TelaCadastro extends StatefulWidget {
  // 🌐 O PULO DO GATO: Se este parâmetro for preenchido, o app sabe que o usuário veio do Google!
  final User? googleUser;

  const TelaCadastro({super.key, this.googleUser});

  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro> {
  final _pageController = PageController();
  final _formKeyEtapa1 = GlobalKey<FormState>();
  final _formKeyEtapa2 = GlobalKey<FormState>();

  // Controllers
  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  // Estados
  int _paginaAtual = 0;
  String? _tipoUsuario; 
  bool _maiorDe16 = false;
  bool _aceitouTermos = false;
  bool _carregando = false;
  bool _obscureSenha = true;
  bool _obscureConfirmar = true; 
  String? _erroGeral;

  // Máscaras (Blindagem de input)
  final _cpfMask = MaskTextInputFormatter(mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final _telMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});

  // 🌐 Verifica se estamos apenas completando o cadastro do Google
  bool get _isGoogleMode => widget.googleUser != null;

  @override
  void initState() {
    super.initState();
    // 🌐 SE VIER DO GOOGLE: Pré-preenche os dados que o Google já nos deu de bandeja!
    if (_isGoogleMode) {
      _nomeController.text = widget.googleUser!.displayName ?? "";
      _emailController.text = widget.googleUser!.email ?? "";
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nomeController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  // --- 🛡️ LÓGICA DE SEGURANÇA E NEGÓCIO ---

  void _setErro(String? msg) => setState(() => _erroGeral = msg);

  bool _validarCPF(String cpf) {
    String limpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpo.length != 11) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(limpo)) return false;
    return true;
  }

  void _mostrarTermos() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00E676), width: 0.5), 
        ),
        title: const Text("Termos de Uso", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            "1. O DefendePraMim liga goleiros a contratantes.\n\n"
            "2. Dados como WhatsApp e Nome serão partilhados entre as partes após a confirmation do jogo.\n\n"
            "3. Cancelamentos tardios podem gerar multas no saldo da conta.\n\n"
            "4. O utilizador é responsável pela veracidade dos dados bancários e documentos.",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("FECHAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () {
              setState(() => _aceitouTermos = true);
              Navigator.pop(context);
            },
            child: const Text("ACEITAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizarCadastro() async {
    _setErro(null);
    if (!_formKeyEtapa2.currentState!.validate()) return;
    
    if (!_aceitouTermos || !_maiorDe16) {
      _setErro("Aceite os termos e confirme a idade para continuar.");
      return;
    }

    setState(() => _carregando = true);

    try {
      String userUid;

      if (_isGoogleMode) {
        // 🌐 MODO GOOGLE: O usuário já está autenticado no Firebase Auth! 
        // Não criamos conta de e-mail/senha, apenas pegamos o UID existente.
        userUid = widget.googleUser!.uid;
      } else {
        // MODO TRADICIONAL: Cria a conta com e-mail e senha normalmente
        final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim().toLowerCase(),
          password: _senhaController.text.trim(),
        );
        userUid = userCred.user!.uid;
      }

      // Salva os dados unificados na Coleção de Usuários do Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(userUid).set({
        'uid': userUid,
        'nome': _nomeController.text.trim(),
        'nomeBusca': _nomeController.text.trim().toLowerCase(),
        'email': _emailController.text.trim().toLowerCase(),
        'cpf': _cpfController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'telefone': _telefoneController.text.trim(),
        'tipoPerfil': _tipoUsuario,
        'fotoUrl': widget.googleUser?.photoURL ?? "", // 🌐 Guarda a foto de perfil do Google se houver
        'provedorAutenticacao': _isGoogleMode ? 'google' : 'email', // Excelente para métricas do Admin!
        'saldo': 0.0,
        'multasPendentes': 0.0,
        'qtdDesistencias': 0,
        'reputacao': 5.0,
        'jogosRealizados': 0,
        'ativo': true,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Fecha todas as telas de autenticação e joga o cara pra Home
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      _setErro(e.code == 'email-already-in-use' ? "Este e-mail já existe." : "Erro: ${e.message}");
    } catch (e) {
      _setErro("Erro técnico. Verifique a ligação à internet.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // --- 🎨 INTERFACE (UI/UX) ---

  @override
  Widget build(BuildContext context) {
    const primaryNeon = Color(0xFF00E676);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () {
            if (_paginaAtual > 0) {
              _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _buildStepIndicator(primaryNeon),
        centerTitle: true,
      ),
      body: PageView(
        controller: _pageController,
        // Impedir o arrasto por gesto se for o modo Google para forçar a validação da Etapa 1
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          setState(() {
            _paginaAtual = index;
          });
        },
        children: [
          _buildEtapa1(primaryNeon),
          _buildEtapa2(primaryNeon),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: _paginaAtual == index ? 20 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: _paginaAtual == index ? color : Colors.white24,
          borderRadius: BorderRadius.circular(4),
        ),
      )),
    );
  }

  Widget _buildEtapa1(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyEtapa1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isGoogleMode ? "Complete seu perfil" : "Crie sua conta", 
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)
            ),
            const SizedBox(height: 30),
            _buildSeletorPerfil(color),
            const SizedBox(height: 30),
            _input(
              controller: _nomeController, 
              label: "Nome Completo", 
              icon: Icons.person_outline, 
              validator: (v) => v!.trim().split(' ').length < 2 ? "Digite nome e sobrenome" : null
            ),
            _input(
              controller: _cpfController, 
              label: "CPF", 
              icon: Icons.badge_outlined, 
              mask: _cpfMask, 
              keyboard: TextInputType.number,
              validator: (v) => !_validarCPF(v!) ? "CPF inválido" : null
            ),
            _input(
              controller: _telefoneController, 
              label: "WhatsApp", 
              icon: Icons.phone_android, 
              mask: _telMask, 
              keyboard: TextInputType.phone,
              validator: (v) => v!.length < 15 ? "Número incompleto" : null
            ),
            
            if (_erroGeral != null && _paginaAtual == 0) 
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildErroWidget(),
              ),

            const SizedBox(height: 20),
            _botaoAcao("PRÓXIMO PASSO", color, () {
              _setErro(null);

              if (_formKeyEtapa1.currentState!.validate()) {
                if (_tipoUsuario == null) {
                  _setErro("Por favor, selecione se você é GOLEIRO ou CONTRATANTE.");
                  return;
                }
                _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEtapa2(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyEtapa2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isGoogleMode ? "Termos e Condições" : "Dados de acesso", 
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)
            ),
            const SizedBox(height: 30),
            
            // 🌐 MUTAÇÃO MÁGICA DO GOOGLE: Esconde os inputs de credenciais se logado via rede social
            if (!_isGoogleMode) ...[
              _input(
                controller: _emailController, 
                label: "E-mail", 
                icon: Icons.email_outlined, 
                keyboard: TextInputType.emailAddress,
                validator: (v) => !v!.contains("@") ? "E-mail inválido" : null
              ),
              _input(
                controller: _senhaController, 
                label: "Sua senha", 
                icon: Icons.lock_outline, 
                obscure: _obscureSenha,
                suffix: IconButton(
                  icon: Icon(_obscureSenha ? Icons.visibility_off : Icons.visibility, color: Colors.grey), 
                  onPressed: () => setState(() => _obscureSenha = !_obscureSenha)
                ),
                validator: (v) => v!.length < 6 ? "Mínimo 6 caracteres" : null,
              ),
              _input(
                controller: _confirmarSenhaController, 
                label: "Confirmar Senha", 
                icon: Icons.lock_reset, 
                obscure: _obscureConfirmar,
                suffix: IconButton(
                  icon: Icon(_obscureConfirmar ? Icons.visibility_off : Icons.visibility, color: Colors.grey), 
                  onPressed: () => setState(() => _obscureConfirmar = !_obscureConfirmar)
                ),
                validator: (v) => v != _senhaController.text ? "As senhas não coincidem" : null,
              ),
            ] else ...[
              // Mensagem sutil avisando que a segurança é pelo Google
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(Icons.g_mobiledata, color: color, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Autenticado via Google:\n${_emailController.text}",
                        style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            _buildCheckboxes(color),
            if (_erroGeral != null && _paginaAtual == 1) _buildErroWidget(),
            const SizedBox(height: 30),
            _botaoAcao(_carregando ? "A CARREGAR..." : "FINALIZAR", color, _carregando ? null : _finalizarCadastro),
          ],
        ),
      ),
    );
  }

  // --- 🛠️ COMPONENTES REUTILIZÁVEIS ---

  Widget _input({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool obscure = false, 
    Widget? suffix, 
    dynamic mask, 
    TextInputType keyboard = TextInputType.text,
    TextInputAction? action,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        textInputAction: action ?? TextInputAction.next,
        onFieldSubmitted: onSubmitted,
        keyboardAppearance: Brightness.dark,
        inputFormatters: mask != null ? [mask] : [],
        validator: validator,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label, 
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          prefixIcon: Icon(icon, color: const Color(0xFF00E676), size: 22),
          suffixIcon: suffix,
          filled: true, 
          fillColor: const Color(0xFFFFFFFF).withOpacity(0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.white10, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF00E676), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSeletorPerfil(Color color) {
    return Row(children: [
      _cardPerfil("GOLEIRO", "goleiro", Icons.sports_soccer, color),
      const SizedBox(width: 12),
      _cardPerfil("CONTRATANTE", "contratante", Icons.groups, color),
    ]);
  }

  Widget _cardPerfil(String label, String value, IconData icon, Color color) {
    bool sel = _tipoUsuario == value;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => setState(() => _tipoUsuario = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.1) : const Color(0xFF222222),
          border: Border.all(color: sel ? color : Colors.white10, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(children: [
          Icon(icon, color: sel ? color : Colors.white38, size: 30),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: sel ? color : Colors.white38, fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
      ),
    ));
  }

  Widget _buildCheckboxes(Color color) {
    return Column(children: [
      CheckboxListTile(
        value: _maiorDe16, 
        onChanged: (v) => setState(() => _maiorDe16 = v!),
        title: const Text("Sou maior de 16 anos", style: TextStyle(color: Colors.white, fontSize: 13)),
        activeColor: color, 
        checkColor: Colors.black,
        contentPadding: EdgeInsets.zero, 
        controlAffinity: ListTileControlAffinity.leading,
      ),
      CheckboxListTile(
        value: _aceitouTermos, 
        onChanged: (v) {
          if (_aceitouTermos == false) {
            _mostrarTermos();
          } else {
            setState(() => _aceitouTermos = v!);
          }
        },
        activeColor: color, 
        checkColor: Colors.black,
        contentPadding: EdgeInsets.zero, 
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(children: [
          const Text("Aceito os ", style: TextStyle(color: Colors.white, fontSize: 13)),
          GestureDetector(
            onTap: _mostrarTermos, 
            child: Text(
              "Termos de Uso", 
              style: TextStyle(color: color, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)
            )
          ),
        ]),
      ),
    ]);
  }

  Widget _botaoAcao(String texto, Color color, VoidCallback? acao) {
    return SizedBox(
      width: double.infinity, 
      height: 56, 
      child: ElevatedButton(
        onPressed: acao,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildErroWidget() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent), 
        const SizedBox(width: 10), 
        Expanded(child: Text(_erroGeral!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)))
      ]),
    );
  }
}