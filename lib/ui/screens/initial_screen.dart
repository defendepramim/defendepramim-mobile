import 'package:defendepramim/ui/screens/cadastro_screen.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  static const Color primaryNeon = Color(0xFF00E676);
  static const Color backgroundColor = Color(0xFF1E1E1E);

  bool _carregandoGoogle = false;

  /// 🌐 O MOTOR DE BUSCA: Lógica de Autenticação e Redirecionamento
Future<void> _entrarComGoogle() async {
    setState(() => _carregandoGoogle = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
      );
      
      // 🟢 A MARRETA NO CACHE: Limpa qualquer conta lembrada antes de abrir a janela!
      await googleSignIn.signOut(); 
      
      // Agora sim ele chama a tela e é obrigado a perguntar qual conta usar
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        setState(() => _carregandoGoogle = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        final docUser = await FirebaseFirestore.instance.collection('usuarios').doc(firebaseUser.uid).get();

        if (!mounted) return;

        if (docUser.exists) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TelaCadastro(googleUser: firebaseUser),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Erro no Google SignIn: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Falha ao entrar com Google: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _carregandoGoogle = false);
    }
  }

  /// 📜 EXIBE OS TERMOS DE USO (POPUP GIGANTE PREPARADO PARA TEXTO LONGO)
  void _showTermsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Transparente para o Container desenhar a borda
      isScrollControlled: true, // Permite que o modal ocupe mais espaço
      builder: (context) {
        return Container(
          // Força o popup a ocupar 85% da altura da tela
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 80),
              child: Column(
                children: [
                  // Indicador visual de arrastar para fechar (Premium Touch)
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Ícone de Escudo / Regras
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF2E2E2E),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 32,
                      color: primaryNeon,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text(
                    "Termos & Privacidade",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // O Expanded + SingleChildScrollView garante que o texto possa ser gigante no futuro e tenha scroll
                  const Expanded(
                    child: SingleChildScrollView(
                      physics: BouncingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          "🚧 EM CONSTRUÇÃO 🚧\n\nEstamos finalizando nossas diretrizes legais de privacidade e segurança financeira. Nosso compromisso é blindar os dados e transações de todos os goleiros e contratantes da plataforma.\n\n(No futuro, os termos reais entrarão aqui e o usuário poderá rolar o texto tranquilamente até o final para então clicar no botão abaixo.)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Botão de Fechar Modal fixado no rodapé do popup
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryNeon,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "ENTENDIDO",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double logoHeight = MediaQuery.of(context).size.height * 0.26;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  children: [
                    const SizedBox(height: 56), 

                    /// ⚽ LOGO
                    Hero(
                      tag: 'logo',
                      child: Container(
                        height: logoHeight,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
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
                      "DefendePraMim",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Encontre o goleiro ideal para o seu time.",
                      style: TextStyle(fontSize: 16, color: Colors.white54),
                    ),

                    const SizedBox(height: 40),

                    /// 🟢 BOTÕES OTIMIZADOS
                    _buildButton(
                      label: "ENTRAR COM E-MAIL",
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      color: primaryNeon,
                      textColor: Colors.black,
                    ),

                    const SizedBox(height: 12),

                    _buildOutlinedButton(
                      label: "CRIAR MINHA CONTA",
                      onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                      color: primaryNeon,
                    ),

                    const SizedBox(height: 24),

                    /// ➖ DIVIDER
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Colors.white10)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "OU", 
                            style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.white10)),
                      ],
                    ),

                    const SizedBox(height: 24),

                    /// 🔴 BOTÃO GOOGLE COM LOADING E LÓGICA DE DECISÃO
                    _buildSocialButton(
                      onPressed: _carregandoGoogle ? () {} : _entrarComGoogle,
                      isLoading: _carregandoGoogle,
                    ),

                    const Spacer(),

                    /// 📜 TERMOS DE USO
                    TextButton(
                      onPressed: () => _showTermsModal(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      ),
                      child: const Text(
                        "Termos de Uso e Privacidade",
                        style: TextStyle(
                          color: Colors.white60, 
                          fontSize: 13, 
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 64), 
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label, 
    required VoidCallback onPressed, 
    required Color color, 
    required Color textColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildOutlinedButton({
    required String label, 
    required VoidCallback onPressed, 
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }

  Widget _buildSocialButton({required VoidCallback onPressed, required bool isLoading}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white24, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.transparent,
        ),
        child: isLoading 
            ? const SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    "assets/google.png",
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) {
                      return const FaIcon(
                        FontAwesomeIcons.google, 
                        size: 18, 
                        color: Colors.white, 
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "CONTINUAR COM GOOGLE", 
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}