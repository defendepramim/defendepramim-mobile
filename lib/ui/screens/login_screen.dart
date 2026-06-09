import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🟢 IMPORT ADICIONADO PARA LER O BANCO
import 'package:flutter/services.dart';
import '../widgets/campo_input.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  
  bool _carregando = false;
  bool _obscureSenha = true;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _mostrarMensagem(String mensagem, {bool erro = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.redAccent : const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// 🛡️ LÓGICA: RECUPERAR SENHA (COM VERIFICAÇÃO INTELIGENTE)
  Future<void> _recuperarSenha() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _mostrarMensagem("Digite seu e-mail para receber o link de recuperação.");
      return;
    }

    setState(() => _carregando = true);
    FocusManager.instance.primaryFocus?.unfocus(); // Baixa o teclado

    try {
      // 1. Vai no nosso banco e verifica se existe algum usuário com esse e-mail
      final userQuery = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      // 2. Se a lista voltar vazia, o e-mail não existe no app!
      if (userQuery.docs.isEmpty) {
        _mostrarMensagem("Este e-mail não está cadastrado no sistema.");
        setState(() => _carregando = false);
        return;
      }

      // 3. Se existe, aí sim a gente manda o link oficial do Firebase
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _mostrarMensagem("Link enviado! Verifique sua caixa de entrada.", erro: false);
      
    } catch (e) {
      _mostrarMensagem("Erro ao processar solicitação. Tente novamente mais tarde.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// 🔑 LÓGICA: LOGIN
  Future<void> _fazerLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final senha = _senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      _mostrarMensagem("Preencha todos os campos.");
      return;
    }

    setState(() => _carregando = true);
    
    // Fecha o teclado antes de iniciar o processo pesado de login
    FocusManager.instance.primaryFocus?.unfocus(); 

    try {
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      final user = userCred.user;

      // 🟢 A PORTA GIRATÓRIA DA SEGURANÇA: Verifica se o e-mail foi validado
      if (user != null && !user.emailVerified) {
        // O e-mail não foi verificado ainda!
        await FirebaseAuth.instance.signOut(); // Desloga o teimoso na hora
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Você precisa verificar seu e-mail antes de entrar."),
              backgroundColor: Colors.orangeAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'REENVIAR E-MAIL',
                textColor: Colors.black,
                backgroundColor: const Color(0xFF00E676),
                onPressed: () async {
                  try {
                     final tempUser = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: senha);
                     await tempUser.user!.sendEmailVerification();
                     await FirebaseAuth.instance.signOut();
                     _mostrarMensagem("Novo link enviado! Olhe o spam.", erro: false);
                  } catch (e) {
                     _mostrarMensagem("Erro ao reenviar. Tente novamente mais tarde.");
                  }
                },
              ),
            ),
          );
        }
        return; // Interrompe o login e não deixa passar pra Home!
      }

      // Se passou pela porta giratória (e-mail tá ok), vai pra Home!
      if (mounted) {
        Navigator.pop(context); // Fecha a tela de login
      }
      
    } on FirebaseAuthException catch (e) {
      String mensagem = "E-mail ou senha incorretos.";
      if (e.code == 'user-disabled') mensagem = "Conta desativada.";
      else if (e.code == 'too-many-requests') mensagem = "Muitas tentativas. Aguarde.";
      
      _mostrarMensagem(mensagem);
    } catch (e) {
      _mostrarMensagem("Erro inesperado.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryNeon = Color(0xFF00E676);
    
    // ✨ CORREÇÃO DE PERFORMANCE AQUI: 
    // Usamos a LARGURA da tela em vez da altura. 
    final double logoSize = MediaQuery.of(context).size.width * 0.45; 
    
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            // 🚀 MÁGICA DE PERFORMANCE: ClampingScrollPhysics impede que o Android tente
            // calcular o efeito elástico invisível quando o teclado "esmaga" a tela.
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                /// ⚽ LOGO HERO
                Hero(
                  tag: 'logo', 
                  child: SizedBox(
                    height: logoSize, 
                    width: logoSize,
                    child: Image.asset(
                      "assets/logo.png",
                      fit: BoxFit.contain,
                      cacheHeight: 400, 
                      errorBuilder: (context, error, stackTrace) => 
                        const Icon(Icons.sports_soccer, size: 140, color: primaryNeon),
                    ),
                  ),
                ),

                const SizedBox(height: 15),
                const Text(
                  "Bem-vindo de volta!",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Acesse sua conta para entrar em campo.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                
                const SizedBox(height: 30),

                /// EMAIL (Ação: Next)
                CampoInput(
                  controller: _emailController,
                  label: "Seu e-mail",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

                /// SENHA (Ação: Done + Login Automático)
                CampoInput(
                  controller: _senhaController,
                  label: "Sua senha",
                  icon: Icons.lock_outline,
                  obscure: _obscureSenha,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _fazerLogin(), 
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureSenha ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(() => _obscureSenha = !_obscureSenha),
                  ),
                ),

                /// ESQUECI MINHA SENHA
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _carregando ? null : _recuperarSenha,
                    child: const Text(
                      "Esqueceu a senha?",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                /// BOTÃO LOGIN
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _carregando ? null : _fazerLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryNeon,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: primaryNeon.withAlpha(76),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                    ),
                    child: _carregando
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                          )
                        : const Text(
                            "ENTRAR NA CONTA",
                            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                /// CADASTRAR-SE
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Novo por aqui?", style: TextStyle(color: Colors.grey)),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                      child: const Text(
                        "Crie sua conta",
                        style: TextStyle(color: primaryNeon, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}