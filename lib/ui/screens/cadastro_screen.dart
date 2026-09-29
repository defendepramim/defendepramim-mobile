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
  bool _maiorDe18 = false;
  bool _aceitouTermos = false;
  bool _carregando = false;
  bool _obscureSenha = true;
  bool _obscureConfirmar = true; 
  String? _erroGeral;

  bool _isGoogleMode = false;
  User? _usuarioLogado; 

  final _cpfMask = MaskTextInputFormatter(mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final _telMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});

  String? _erroEmailAsync;

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
    FocusManager.instance.primaryFocus?.unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, 
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 20),
                  const Text("Termos & Privacidade", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 16),
                  const Expanded(
                    child: SingleChildScrollView(
                      physics: BouncingScrollPhysics(),
                      child: Text(
'''TERMOS E CONDIÇÕES DE USO E POLÍTICA DE PRIVACIDADE
Aplicativo Defende Pra Mim

Bem-vindo(a) ao Defende Pra Mim. Ao criar uma conta e utilizar nosso aplicativo, você concorda expressamente com as regras abaixo. Leia com atenção, pois este documento é um contrato legal entre você (Usuário) e a plataforma.

1. NATUREZA DO SERVIÇO (SOMOS APENAS UM APLICATIVO)
O Defende Pra Mim é exclusivamente uma plataforma de tecnologia (Marketplace) que facilita a conexão entre organizadores de partidas de futebol ("Contratantes") e goleiros amadores/profissionais ("Goleiros"). Nós não organizamos os jogos, não somos donos das quadras e não prestamos serviços esportivos.

2. INEXISTÊNCIA DE VÍNCULO EMPREGATÍCIO
Fica expressamente declarado e reconhecido que não existe qualquer vínculo empregatício, de subordinação, exclusividade, sociedade ou relação de trabalho entre o Defende Pra Mim e os Goleiros cadastrados.
• O Goleiro atua de forma autônoma, escolhendo livremente quais convocações aceitar.
• A plataforma atua apenas como agente facilitador.

3. ISENÇÃO DE RESPONSABILIDADE CIVIL E FÍSICA
A prática esportiva envolve riscos inerentes. Ao utilizar a plataforma, o Usuário assume integralmente os riscos de sua participação nas partidas.
• O Defende Pra Mim não se responsabiliza por lesões físicas, acidentes, danos materiais, danos morais, desentendimentos, furtos ou qualquer incidente ocorrido nas quadras.
• A plataforma não fornece seguro de saúde ou seguro de vida aos usuários.

4. POLÍTICA DE CANCELAMENTOS, FALTAS E MULTAS
Para garantir a confiabilidade da plataforma para todos, aplicamos regras financeiras estritas:
• Cancelamento Tardio ou No-Show (Falta): O Usuário que cancelar uma partida fora do prazo de carência estabelecido, ou que não comparecer ao jogo, estará sujeito a uma multa automática.
• Transparência de Valores: O valor exato da multa e o tempo limite de antecedência para cancelamento gratuito são dinâmicos. Eles estarão sempre informados de forma clara na tela de confirmação antes de o Usuário aceitar o convite para a partida.
• Autorização de Desconto: O Usuário autoriza expressamente que a plataforma retenha ou desconte o valor de multas pendentes de seus saldos futuros.

5. PAGAMENTOS E TAXAS DE INTERMEDIAÇÃO
• A plataforma cobra uma taxa de intermediação sobre as partidas finalizadas com sucesso, cujo valor é descontado automaticamente antes do repasse ao Goleiro.
• A plataforma reserva-se o direito de reter temporariamente fundos em caso de suspeita de fraude, contestações ou descumprimento destes Termos.

6. POLÍTICA DE PRIVACIDADE E LGPD
Coletamos apenas os dados estritamente necessários para o funcionamento do app:
• Dados Cadastrais e Financeiros: Nome, CPF, Telefone, E-mail e Chave PIX são armazenados em ambiente seguro e utilizados exclusivamente para emissão de notas e pagamentos.
• Geolocalização (GPS): Coletamos a sua localização em segundo plano exclusivamente para notificar o Goleiro sobre partidas próximas.
• Não vendemos seus dados. Seu nome será exibido para outros usuários apenas no contexto da partida confirmada.

7. BLOQUEIO E EXCLUSÃO DE CONTA
O Defende Pra Mim preza pelo respeito. Reservamo-nos o direito de banir permanentemente usuários que cometerem agressões, praticarem fraudes ou acumularem sucessivas faltas injustificadas.

8. DIREITOS DE IMAGEM E MARKETING
O Usuário autoriza, de forma gratuita, o uso de seu primeiro nome e foto de perfil (quando cadastrada) em materiais de divulgação institucional e publicitária do próprio Defende Pra Mim (como redes sociais e campanhas do app), respeitando sempre a moral, a boa-fé e o contexto esportivo.

Ao criar sua conta, você declara ser maior de 18 anos, ter lido, compreendido e aceitado todos os termos acima.''',
                        style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("FECHAR", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _aceitouTermos = true);
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("ACEITAR", style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 🟢 ETAPA 2: A CONTA JÁ FOI CRIADA NO PASSO 1, SÓ SALVAMOS NO BANCO
  Future<void> _finalizarCadastro() async {
    _setErro(null);
    
    if (_isGoogleMode) {
      if (!_formKeyGoogle.currentState!.validate()) return;
    } else {
      if (!_formKeyEtapa2.currentState!.validate()) return;
    }
    
    if (_tipoUsuario == null) {
      _setErro("Por favor, selecione se você é GOLEIRO ou CONTRATANTE.");
      return;
    }

    if (!_aceitouTermos || !_maiorDe18) {
      _setErro("Aceite os termos e confirme a idade para continuar.");
      return;
    }

    setState(() => _carregando = true);

    try {
      // Como o cara já passou da Etapa 1, a conta já existe no Auth! Só pegamos o ID.
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception("Sessão expirada. Volte e tente novamente.");

      String userUid = currentUser.uid;

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
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      debugPrint("🚨 ERRO NO FIRESTORE: $e");
      _setErro("Erro real: $e");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // 🟢 SE ELE DESISTIR NA ETAPA 2, APAGAMOS A CONTA SILENCIOSA
  Future<void> _acaoVoltar() async {
    if (_isGoogleMode) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } else {
      if (_paginaAtual == 1) {
        try {
          // Apaga o e-mail criado caso ele mude de ideia e queira voltar
          await FirebaseAuth.instance.currentUser?.delete();
        } catch (_) {} 
        setState(() => _paginaAtual = 0);
      } else {
        if (mounted) {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryNeon = Color(0xFF00E676);

    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _acaoVoltar(); 
      },
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildTelaUnicaGoogle(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20), 
      child: Form(
        key: _formKeyGoogle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Falta pouco!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            const Text("Precisamos apenas de mais alguns dados para ativar sua conta na plataforma.", style: TextStyle(color: Colors.white54, height: 1.3)),
            const SizedBox(height: 20),
            
            _buildSeletorPerfil(color),
            const SizedBox(height: 20),
            
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
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.g_mobiledata, color: color, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Conectado como:\n${_emailController.text}",
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildCheckboxes(color),
            if (_erroGeral != null) _buildErroWidget(),
            const SizedBox(height: 20),
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
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyEtapa1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Dados de acesso", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 6),
            const Text("Crie seu login para entrar no aplicativo.", style: TextStyle(color: Colors.white54, height: 1.3)),
            const SizedBox(height: 20),
            _input(
              controller: _emailController, 
              label: "E-mail", 
              icon: Icons.email_outlined, 
              keyboard: TextInputType.emailAddress,
              forceErrorText: _erroEmailAsync, 
              onChanged: (valor) {
                if (_erroEmailAsync != null) {
                  setState(() => _erroEmailAsync = null);
                }
              },
              validator: (v) {
                if (!v!.contains("@")) return "E-mail inválido";
                if (_erroEmailAsync != null) return _erroEmailAsync; 
                return null;
              }
            ),
            _input(
              controller: _senhaController, 
              label: "Sua senha", 
              icon: Icons.lock_outline, 
              obscure: _obscureSenha,
              suffix: IconButton(
                icon: Icon(_obscureSenha ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20), 
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
                icon: Icon(_obscureConfirmar ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20), 
                onPressed: () => setState(() => _obscureConfirmar = !_obscureConfirmar)
              ),
              validator: (v) => v != _senhaController.text ? "As senhas não coincidem" : null,
            ),
            
            if (_erroGeral != null && _paginaAtual == 0) 
              Padding(padding: const EdgeInsets.only(top: 8), child: _buildErroWidget()),

            const SizedBox(height: 16),
            
            // 🟢 A MÁGICA: CRIA A CONTA AQUI PARA VALIDAR SE O EMAIL EXISTE COM 100% DE CERTEZA
            _botaoAcao(_carregando ? "VERIFICANDO..." : "PRÓXIMO PASSO", color, _carregando ? null : () async {
              _setErro(null);
              setState(() => _erroEmailAsync = null);
              FocusManager.instance.primaryFocus?.unfocus();

              if (_formKeyEtapa1.currentState!.validate()) {
                setState(() => _carregando = true);
                
                try {
                  // O Firebase vai barrar aqui se o email já existir!
                  await FirebaseAuth.instance.createUserWithEmailAndPassword(
                    email: _emailController.text.trim().toLowerCase(),
                    password: _senhaController.text.trim(),
                  );
                  // Passou ileso? Então o e-mail é válido e a conta Auth está criada. Avança!
                  setState(() => _paginaAtual = 1); 
                  
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'email-already-in-use') {
                    try {
                      // Se já existe no Auth mas não no Firestore, loga e avança para a Etapa 2
                      await FirebaseAuth.instance.signInWithEmailAndPassword(
                        email: _emailController.text.trim().toLowerCase(),
                        password: _senhaController.text.trim(),
                      );
                      setState(() => _paginaAtual = 1);
                    } catch (_) {
                      setState(() => _erroEmailAsync = "Este e-mail já está cadastrado.");
                      _formKeyEtapa1.currentState!.validate();
                    }
                  } else {
                    _setErro(e.message);
                  }
                } catch (e) {
                  _setErro("Erro interno: $e");
                } finally {
                  if (mounted) setState(() => _carregando = false);
                }
              }
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEtapa2(Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKeyEtapa2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Complete seu perfil", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            _buildSeletorPerfil(color),
            const SizedBox(height: 20),
            _input(
              controller: _nomeController, 
              label: "Nome Completo", 
              icon: Icons.person_outline, 
              textCapitalization: TextCapitalization.words, 
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

            const SizedBox(height: 10),
            _buildCheckboxes(color),
            if (_erroGeral != null && _paginaAtual == 1) _buildErroWidget(),
            const SizedBox(height: 20),
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
    void Function(String)? onChanged, 
    TextCapitalization textCapitalization = TextCapitalization.none,
    FocusNode? focusNode, 
    String? forceErrorText, 
    // 🟢 1. Adicionamos o parâmetro aqui com o padrão de interação
    AutovalidateMode autovalidateMode = AutovalidateMode.onUserInteraction, 
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode, 
        obscureText: obscure,
        keyboardType: keyboard,
        textInputAction: action ?? TextInputAction.next,
        onFieldSubmitted: onSubmitted,
        onChanged: onChanged, 
        inputFormatters: mask != null ? [mask] : [],
        validator: validator,
        textCapitalization: textCapitalization,
        // 🟢 2. Ativamos a validação em tempo real no TextFormField
        autovalidateMode: autovalidateMode, 
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label, 
          errorText: forceErrorText, 
          labelStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF00E676), size: 20),
          suffixIcon: suffix,
          filled: true, 
          fillColor: const Color(0xFFFFFFFF).withAlpha(13), 
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00E676), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
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
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _tipoUsuario = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: sel ? color.withAlpha(26) : const Color(0xFF222222), 
          border: Border.all(color: sel ? color : Colors.white10, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, color: sel ? color : Colors.white38, size: 26),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: sel ? color : Colors.white38, fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
      ),
    ));
  }

  Widget _buildCheckboxes(Color color) {
    return Column(
      children: [
        CheckboxListTile(
          value: _maiorDe18, 
          onChanged: (v) {
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _maiorDe18 = v ?? false);
          },
          dense: true, 
          visualDensity: VisualDensity.compact, 
          title: const Text("Sou maior de 18 anos", style: TextStyle(color: Colors.white, fontSize: 12)),
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
          dense: true, 
          visualDensity: VisualDensity.compact, 
          activeColor: color, 
          checkColor: Colors.black,
          contentPadding: EdgeInsets.zero, 
          controlAffinity: ListTileControlAffinity.leading,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("Li e concordo com os ", style: TextStyle(color: Colors.white, fontSize: 12)),
              GestureDetector(
                onTap: _mostrarTermos, 
                child: Text(
                  "Termos de Uso", 
                  style: TextStyle(color: color, decoration: TextDecoration.underline, fontWeight: FontWeight.bold, fontSize: 12)
                )
              ),
            ],
          ),
          subtitle: const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              "(Entendo que o app é apenas uma plataforma de conexão, assumo os riscos físicos normais do esporte e concordo que cancelamentos fora do prazo informado geram multas descontadas do meu saldo).",
              style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _botaoAcao(String texto, Color color, VoidCallback? acao) {
    return SizedBox(
      width: double.infinity, 
      height: 50, 
      child: ElevatedButton(
        onPressed: acao,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(texto, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildErroWidget() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(26), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withAlpha(51)), 
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20), 
        const SizedBox(width: 8), 
        Expanded(child: Text(_erroGeral!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)))
      ]),
    );
  }
}