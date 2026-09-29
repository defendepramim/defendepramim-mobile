import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'tabs_contratante/aba_meus_jogos.dart';
import 'tabs_contratante/aba_financeiro.dart';
import 'tabs_contratante/aba_perfil.dart';

import 'convocacao/tela_criar_jogo.dart';
import '../widgets/custom_app_bar.dart';

class HomeContratante extends StatefulWidget {
  final int indiceInicial;
  
  const HomeContratante({super.key, this.indiceInicial = 0});

  @override
  State <HomeContratante> createState() => _HomeContratanteState();
}

class _HomeContratanteState extends State <HomeContratante> {
  late int _abaAtual;
  bool _exibirCriarJogo = false;

  final Color primaryColor = const Color(0xFF00E676);
  final Color backgroundColor = const Color(0xFF121212);
  final Color surfaceColor = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    _abaAtual = widget.indiceInicial; 
    _solicitarPermissoesEssenciais();
  }

  Future _solicitarPermissoesEssenciais() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }
  }

  void _alternarCriacao(bool exibir) {
    setState(() {
      _exibirCriarJogo = exibir;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_exibirCriarJogo,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (_exibirCriarJogo) {
          _alternarCriacao(false);
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        
        appBar: CustomAppBar(
          titulo: _exibirCriarJogo ? "NOVA CONVOCAÇÃO" : "DefendePraMim",
          exibirBotaoFechar: _exibirCriarJogo && _abaAtual == 0,
          onBotaoFecharPressionado: () => _alternarCriacao(false),
        ),
        
        body: IndexedStack(
          index: _abaAtual,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _exibirCriarJogo 
                  ? TelaCriarJogo(onFinalizado: () => _alternarCriacao(false)) 
                  : const AbaMeusJogos(),
            ),
            const AbaFinanceiroContratante(),
            const AbaPerfilContratante(),
          ],
        ),

        floatingActionButton: _buildFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget? _buildFAB() {
    if (_abaAtual != 0 || _exibirCriarJogo) return null;

    return FloatingActionButton.extended(
      onPressed: () => _alternarCriacao(true),
      backgroundColor: primaryColor,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      icon: const Icon(Icons.add_rounded, color: Colors.black, size: 28),
      label: const Text(
        "CONVOCAR GOLEIRO",
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(76), blurRadius: 10, spreadRadius: 2)
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _abaAtual,
        onTap: (index) {
          if (_exibirCriarJogo && index != 0) {
            _alternarCriacao(false);
          }
          setState(() => _abaAtual = index);
        },
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white24,
        backgroundColor: surfaceColor,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer_outlined), 
            activeIcon: Icon(Icons.sports_soccer),
            label: 'Jogos'
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined), 
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Financeiro'
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded), 
            activeIcon: Icon(Icons.person_rounded),
            label: 'Perfil'
          ),
        ],
      ),
    );
  }
}