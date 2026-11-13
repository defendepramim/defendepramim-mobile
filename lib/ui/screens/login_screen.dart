import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../widgets/campo_input.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State< LoginScreen > createState() => _LoginScreenState();
}

class _LoginScreenState extends State< LoginScreen > {
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

  /// 🛡️ LÓGICA: RECUPERAR SENHA (BLINDADA)
  Future< void > _recuperarSenha() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _mostrarMensagem("Digite seu e-mail para receber o link de recuperação.");
      return;
    }

    setState(() => _carregando = true);
    FocusManager.instance.primaryFocus?.unfocus(); 

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _mostrarMensagem("Se o e-mail estiver cadastrado, enviaremos um link de recuperação.", erro: false);
    } catch (e) {
      _mostrarMensagem("Se o e-mail estiver cadastrado, enviaremos um link de recuperação.", erro: false);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// 🔑 LÓGICA: LOGIN
  Future< void > _fazerLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final senha = _senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      _mostrarMensagem("Preencha todos os campos.");
      return;
    }

    setState(() => _carregando = true);
    FocusManager.instance.primaryFocus?.unfocus(); 
    ScaffoldMessenger.of(context).clearSnackBars();

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
      
    } on FirebaseAuthException catch (e) {
      String mensagem = "E-mail ou senha incorretos.";
      if (e.code == 'user-disabled') {
        mensagem = "Conta desativada.";
      } else if (e.code == 'too-many-requests') {
        mensagem = "Muitas tentativas. Aguarde.";
      }
      
      _mostrarMensagem(mensagem);
    } catch (e) {
      _mostrarMensagem("Erro inesperado ao tentar aceder.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryNeon = Color(0xFF00E676);
    const double logoSize = 180.0; 
    
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
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                Hero(
                  tag: 'logo', 
                  child: RepaintBoundary( 
                    child: SizedBox(
                      height: logoSize, 
                      width: logoSize,
                      child: Image.asset(
                        "assets/logo.png",
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => 
                          const Icon(Icons.sports_soccer, size: 140, color: primaryNeon),
                      ),
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

                CampoInput(
                  controller: _emailController,
                  label: "Seu e-mail",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 16),

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