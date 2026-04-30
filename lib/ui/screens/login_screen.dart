import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../widgets/campo_input.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  
  bool _carregando = false;
  bool _obscureSenha = true;

  late AnimationController _animController;
  late Animation<double> _animLogo;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _animLogo = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _mostrarMensagem(String mensagem, {bool erro = true}) {
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
      _mostrarMensagem("Erro ao enviar e-mail. Verifique o endereço digitado.");
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
    FocusScope.of(context).unfocus(); // Fecha o teclado

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: senha,
      );

      if (mounted) {
        // Sucesso: Volta para o AuthCheck que redirecionará para a Home
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      // Segurança: Mensagem genérica para evitar enumeração de e-mails
      String mensagem = "E-mail ou senha incorretos.";
      
      if (e.code == 'user-disabled') {
        mensagem = "Esta conta foi desativada pelo suporte.";
      } else if (e.code == 'too-many-requests') {
        mensagem = "Muitas tentativas. Tente novamente mais tarde.";
      }
      
      _mostrarMensagem(mensagem);
    } catch (e) {
      _mostrarMensagem("Ocorreu um erro inesperado.");
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryNeon = Color(0xFF00E676);
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              /// ⚽ LOGO ANIMADA (Aumentada)
              ScaleTransition(
                scale: _animLogo,
                child: Hero(
                  tag: 'logo', // Hero animation se vier da tela inicial
                  child: Container(
                    // Aumentado de 0.20 para 0.30 da altura da tela
                    height: MediaQuery.of(context).size.height * 0.30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryNeon.withOpacity(0.08), // Levemente mais visível
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      "assets/logo.png",
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => 
                        const Icon(Icons.sports_soccer, size: 140, color: primaryNeon), // Fallback proporcional
                    ),
                  ),
                ),
              ),

              // Espaço reduzido de 30 para 15 para compensar o aumento da logo
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
              const SizedBox(height: 40),

              /// EMAIL
              CampoInput(
                controller: _emailController,
                label: "Seu e-mail",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 20),

              /// SENHA
              CampoInput(
                controller: _senhaController,
                label: "Sua senha",
                icon: Icons.lock_outline,
                obscure: _obscureSenha,
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
                  child: Text(
                    "Esqueceu a senha?",
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              /// BOTÃO LOGIN (Com tamanho fixo para evitar saltos na UI)
              SizedBox(
                width: double.infinity,
                height: 58,
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
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
                        ),
                ),
              ),

              const SizedBox(height: 25),

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
            ],
          ),
        ),
      ),
    );
  }
}