import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  /// 🛡️ LÓGICA: RECUPERAR SENHA
  Future<void> _recuperarSenha() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _mostrarMensagem("Digite seu e-mail para receber o link de recuperação.");
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _mostrarMensagem("Link enviado! Verifique sua caixa de entrada.", erro: false);
    } catch (e) {
      _mostrarMensagem("Erro ao enviar e-mail. Verifique o endereço.");
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      if (mounted) {
        Navigator.pop(context);
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
    // Quando o teclado sobe, a largura continua a mesma, então o Flutter NÃO recalcula e não engasga a animação!
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
        // ✨ CORREÇÃO DE PERFORMANCE: O HitTestBehavior.translucent otimiza os toques na tela
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                /// ⚽ LOGO HERO
                Hero(
                  tag: 'logo', 
                  child: SizedBox(
                    height: logoSize, // Altura estática blindada contra o teclado
                    width: logoSize,
                    child: Image.asset(
                      "assets/logo.png",
                      fit: BoxFit.contain,
                      cacheHeight: 400, // Excelente manter isso!
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
                      disabledBackgroundColor: primaryNeon.withOpacity(0.3),
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