import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

class TelaCadastro extends StatefulWidget {
  final User? googleUser;
  const TelaCadastro({super.key, this.googleUser});

  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro> {
  final _formKeyEtapa1 = GlobalKey<FormState>();
  final _formKeyEtapa2 = GlobalKey<FormState>();
  final _formKeyGoogle = GlobalKey<FormState>(); 

  final _nomeController = TextEditingController();
  final _cpfController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _confirmarSenhaController = TextEditingController();

  int _paginaAtual = 0;
  String? _tipoUsuario; 
  bool _maiorDe16 = false;
  bool _aceitouTermos = false;
  bool _carregando = false;
  bool _obscureSenha = true;
  bool _obscureConfirmar = true; 
  String? _erroGeral;

  bool _isGoogleMode = false;
  User? _usuarioLogado; 

  final _cpfMask = MaskTextInputFormatter(mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final _telMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    _verificarModoGoogle(); 
  }

  void _verificarModoGoogle() {
    _usuarioLogado = widget.googleUser ?? FirebaseAuth.instance.currentUser;

    if (_usuarioLogado != null) {
      bool veioDoGoogle = _usuarioLogado!.providerData.any((p) => p.providerId == 'google.com');

      if (veioDoGoogle) {
        setState(() {
          _isGoogleMode = true; 
          _nomeController.text = _usuarioLogado!.displayName ?? "";
          _emailController.text = _usuarioLogado!.email ?? "";
        });
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  void _setErro(String? msg) => setState(() => _erroGeral = msg);

  bool _validarCPF(String cpf) {
    String limpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (limpo.length != 11) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(limpo)) return false;
    return true;
  }

  void _mostrarTermos() {
    // 🟢 MATADOR DE TECLADO: Tira o foco antes de abrir o Modal
    FocusManager.instance.primaryFocus?.unfocus();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00E676), width: 0.5), 
        ),
        title: const Text("Termos de Uso", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            "1. O DefendePraMim liga goleiros a contratantes.\n\n"
            "2. Dados como WhatsApp e Nome serão partilhados entre as partes após a confirmação do jogo.\n\n"
            "3. Cancelamentos tardios podem gerar multas no saldo da conta.\n\n"
            "4. O utilizador é responsável pela veracidade dos dados bancários e documentos.",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("FECHAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () {
              setState(() => _aceitouTermos = true);
              Navigator.pop(ctx);
            },
            child: const Text("ACEITAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizarCadastro() async {
    _setErro(null);
    
    if (_isGoogleMode) {
      if (!_formKeyGoogle.currentState!.validate()) return;
      if (_tipoUsuario == null) {
        _setErro("Por favor, selecione seu perfil (Goleiro ou Contratante).");
        return;
      }
    } else {
      if (!_formKeyEtapa2.currentState!.validate()) return;
    }
    
    if (!_aceitouTermos || !_maiorDe16) {
      _setErro("Aceite os termos e confirme a idade para continuar.");
      return;
    }

    setState(() => _carregando = true);

    try {
      String userUid;
      bool precisaVerificarEmail = false; 

      if (_isGoogleMode) {
        userUid = _usuarioLogado!.uid; 
      } else {
        final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim().toLowerCase(),
          password: _senhaController.text.trim(),
        );
        userUid = userCred.user!.uid;
        
        await userCred.user!.sendEmailVerification();
        precisaVerificarEmail = true;
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(userUid).set({
        'uid': userUid,
        'nome': _nomeController.text.trim(),
        'nomeBusca': _nomeController.text.trim().toLowerCase(),
        'email': _emailController.text.trim().toLowerCase(),
        'cpf': _cpfController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        'telefone': _telefoneController.text.trim(),
        'tipoPerfil': _tipoUsuario,
        'fotoUrl': _usuarioLogado?.photoURL ?? "", 
        'provedorAutenticacao': _isGoogleMode ? 'google' : 'email',
        'saldo': 0.0,
        'multasPendentes': 0.0,
        'qtdDesistencias': 0,
        'reputacao': 5.0,
        'jogosRealizados': 0,
        'ativo': true,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        if (precisaVerificarEmail) {
          await FirebaseAuth.instance.signOut();
          
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Falta pouco!", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
              content: const Text(
                "Enviamos um link de confirmação para o seu e-mail. Por favor, clique nele para ativar sua conta antes de fazer o login.",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx); 
                    Navigator.pop(context); 
                  },
                  child: const Text("IR PARA O LOGIN", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      _setErro(e.code == 'email-already-in-use' ? "Este e-mail já existe." : "Erro: ${e.message}");
    } catch (e) {
      debugPrint("🚨 ERRO NO FIRESTORE: $e");
      _setErro("Erro real: $e");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // 🟢 CORREÇÃO DO BOTÃO VOLTAR
  Future<void> _acaoVoltar() async {
    if (_isGoogleMode) {
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pop(context);
    } else {
      if (_paginaAtual == 1) {
        setState(() => _paginaAtual = 0);
      } else {
        if (mounted) Navigator.pop(context);
      }
    }
  }

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
          onPressed: _acaoVoltar,
        ),
        title: _isGoogleMode 
            ? const Text("Finalizar Perfil", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
            : _buildStepIndicator(primaryNeon),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isGoogleMode 
            ? _buildTelaUnicaGoogle(primaryNeon) 
            : IndexedStack(
                index: _paginaAtual,
                children: [
                  _buildEtapa1(primaryNeon),
                  _buildEtapa2(primaryNeon),
                ],
              ),
      ),
    );
  }

  Widget _buildTelaUnicaGoogle(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyGoogle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Falta pouco!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("Precisamos apenas de mais alguns dados para ativar sua conta na plataforma.", style: TextStyle(color: Colors.white54, height: 1.4)),
            const SizedBox(height: 30),
            
            _buildSeletorPerfil(color),
            const SizedBox(height: 30),
            
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
            
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.g_mobiledata, color: color, size: 35),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Conectado como:\n${_emailController.text}",
                      style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildCheckboxes(color),
            if (_erroGeral != null) _buildErroWidget(),
            const SizedBox(height: 30),
            _botaoAcao(_carregando ? "A CARREGAR..." : "CRIAR CONTA", color, _carregando ? null : _finalizarCadastro),
          ],
        ),
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
            const Text("Crie sua conta", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
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
              Padding(padding: const EdgeInsets.only(top: 10), child: _buildErroWidget()),

            const SizedBox(height: 20),
            _botaoAcao("PRÓXIMO PASSO", color, () {
              _setErro(null);
              if (_formKeyEtapa1.currentState!.validate()) {
                if (_tipoUsuario == null) {
                  _setErro("Por favor, selecione se você é GOLEIRO ou CONTRATANTE.");
                  return;
                }
                setState(() => _paginaAtual = 1); 
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
            const Text("Dados de acesso", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 30),
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
              validator: (v) {
                if (v == null || v.isEmpty) return "A senha é obrigatória";
                if (v.length < 8) return "No mínimo 8 caracteres";
                if (!v.contains(RegExp(r'[a-zA-Z]'))) return "Deve conter pelo menos uma letra";
                if (!v.contains(RegExp(r'[0-9]'))) return "Deve conter pelo menos um número";
                return null;
              },
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

            _buildCheckboxes(color),
            if (_erroGeral != null && _paginaAtual == 1) _buildErroWidget(),
            const SizedBox(height: 30),
            _botaoAcao(_carregando ? "A CARREGAR..." : "FINALIZAR", color, _carregando ? null : _finalizarCadastro),
          ],
        ),
      ),
    );
  }

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
        inputFormatters: mask != null ? [mask] : [],
        validator: validator,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label, 
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E)),
          prefixIcon: Icon(icon, color: const Color(0xFF00E676), size: 22),
          suffixIcon: suffix,
          filled: true, 
          fillColor: const Color(0xFFFFFFFF).withAlpha(13), 
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
          color: sel ? color.withAlpha(26) : const Color(0xFF222222), 
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
    return Column(
      children: [
        CheckboxListTile(
          value: _maiorDe16, 
          onChanged: (v) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _maiorDe16 = v ?? false);
          },
          title: const Text("Sou maior de 16 anos", style: TextStyle(color: Colors.white, fontSize: 13)),
          activeColor: color, 
          checkColor: Colors.black,
          contentPadding: EdgeInsets.zero, 
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          value: _aceitouTermos, 
          onChanged: (v) {
            FocusManager.instance.primaryFocus?.unfocus(); 
            if (!_aceitouTermos) {
              _mostrarTermos();
            } else {
              setState(() => _aceitouTermos = v ?? false);
            }
          },
          activeColor: color, 
          checkColor: Colors.black,
          contentPadding: EdgeInsets.zero, 
          controlAffinity: ListTileControlAffinity.leading,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("Aceito os ", style: TextStyle(color: Colors.white, fontSize: 13)),
              GestureDetector(
                onTap: _mostrarTermos, 
                child: Text(
                  "Termos de Uso", 
                  style: TextStyle(color: color, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)
                )
              ),
            ],
          ),
        ),
      ],
    );
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
        color: Colors.redAccent.withAlpha(26), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withAlpha(51)), 
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent), 
        const SizedBox(width: 10), 
        Expanded(child: Text(_erroGeral!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)))
      ]),
    );
  }
}