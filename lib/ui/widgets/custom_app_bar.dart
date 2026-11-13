import 'package:flutter/material.dart';
import 'botao_notificacao.dart';

// O segredo do topo personalizado é implementar o PreferredSizeWidget
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String titulo;
  final bool exibirBotaoFechar;
  final VoidCallback? onBotaoFecharPressionado;

  const CustomAppBar({
    super.key,
    this.titulo = "DefendePraMim",
    this.exibirBotaoFechar = false,
    this.onBotaoFecharPressionado,
  });

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF121212);
    
    return AppBar(
      leadingWidth: 75, // 🟢 Seu ajuste de tamanho perfeito centralizado aqui!
      backgroundColor: backgroundColor,
      elevation: 0,
      leading: exibirBotaoFechar
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onBotaoFecharPressionado,
            )
          : Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(
                  Icons.sports_soccer,
                  color: Color(0xFF00E676),
                  size: 40,
                ),
              ),
            ),
      title: Text(
        titulo,
        style: const TextStyle(
          letterSpacing: 1.4,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      actions: const [
        BotaoNotificacao(), // 🟢 A sineta inteligente já fica embutida aqui dentro!
      ],
    );
  }

  // Define a altura padrão da AppBar no Flutter (56 pixels)
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}