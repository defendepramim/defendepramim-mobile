import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Adicione no pubspec: font_awesome_flutter

class InitialScreen extends StatelessWidget {
  const InitialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    const primaryNeon = Color(0xFF00E676);
    const backgroundColor = Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.05),

              /// ⚽ LOGO COM GLOW
              Container(
                height: screenHeight * 0.30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryNeon.withOpacity(0.1),
                      blurRadius: 60,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Image.asset(
                  "assets/logo.png",
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => 
                    const Icon(Icons.sports_soccer, size: 120, color: primaryNeon),
                ),
              ),

              const Text(
                "DefendePraMim",
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Goleiros de elite para o seu time.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),

              SizedBox(height: screenHeight * 0.06),

              /// 🟢 BOTÃO LOGIN (E-mail)
              _buildButton(
                label: "ENTRAR COM E-MAIL",
                onPressed: () => Navigator.pushNamed(context, '/login'),
                color: primaryNeon,
                textColor: Colors.black,
              ),

              const SizedBox(height: 12),

              /// ⚪ BOTÃO CADASTRO
              _buildOutlinedButton(
                label: "CRIAR MINHA CONTA",
                onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                color: primaryNeon,
              ),

              const SizedBox(height: 20),

              /// ➖ DIVIDER (Visual para separar o Social)
Row(
  children: [
    Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.3))), // Alterado aqui
    const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Text("OU", style: TextStyle(color: Colors.grey, fontSize: 12)),
    ),
    Expanded(child: Divider(color: Colors.grey.withValues(alpha: 0.3))), // Alterado aqui
  ],
),

              const SizedBox(height: 20),

              /// 🔴 BOTÃO GOOGLE (Corrigido para versões novas do Flutter)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: null, // Mantém nulo para ficar desabilitado
                  style: OutlinedButton.styleFrom(
                    // Cor da borda quando o botão está habilitado
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ).copyWith(
                    // Aqui resolvemos o erro: definimos a borda para o estado desabilitado
                    side: WidgetStateProperty.resolveWith<BorderSide?>(
                      (Set<WidgetState> states) {
                        if (states.contains(WidgetState.disabled)) {
                          return BorderSide(color: Colors.white.withValues(alpha: 0.05)); // Borda bem clarinha se desativado
                        }
                        return BorderSide(color: Colors.white.withValues(alpha: 0.2)); // Borda padrão
                      },
                    ),
                  ),
                  icon: FaIcon(
                    FontAwesomeIcons.google, 
                    size: 18, 
                    color: Colors.white.withValues(alpha: 0.3), // O novo padrão do Flutter
                  ),
                  label: Text(
                    "CONTINUAR COM GOOGLE",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), // O novo padrão do Flutter
                      fontWeight: FontWeight.w600
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              /// 📜 TERMOS
              Opacity(
                opacity: 0.5,
                child: Text(
                  "Ao entrar, você concorda com nossos Termos de Uso.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 11, decoration: TextDecoration.underline),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Helper para não repetir código de botão
  Widget _buildButton({required String label, required VoidCallback onPressed, required Color color, required Color textColor}) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
      ),
    );
  }

  Widget _buildOutlinedButton({required String label, required VoidCallback onPressed, required Color color}) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, letterSpacing: 1.1)),
      ),
    );
  }
}