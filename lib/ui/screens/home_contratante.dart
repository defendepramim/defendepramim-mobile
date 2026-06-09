import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // 🟢 INJETADO AQUI
import 'tabs_contratante/aba_meus_jogos.dart';
import 'tabs_contratante/aba_financeiro.dart';
import 'tabs_contratante/aba_perfil.dart';
import 'package:defendepramim/ui/screens/convocacao/tela_criar_jogo.dart';

class HomeContratante extends StatefulWidget {
  const HomeContratante({super.key});

  @override
  State<HomeContratante> createState() => _HomeContratanteState();
}

class _HomeContratanteState extends State<HomeContratante> {
  int _abaAtual = 0;
  bool _exibirCriarJogo = false;

  final Color primaryColor = const Color(0xFF00E676);
  final Color backgroundColor = const Color(0xFF121212);
  final Color surfaceColor = const Color(0xFF1E1E1E);

  // 🟢 MAGIA DAS PERMISSÕES: Roda assim que a tela nasce!
  @override
  void initState() {
    super.initState();
    _solicitarPermissoesEssenciais();
  }

  Future<void> _solicitarPermissoesEssenciais() async {
    // Pede permissão para avisar o contratante quando um goleiro aceitar o jogo
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // Pede localização para o mapa dos jogos
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }
  }

  void _alternarCriacao(bool exibir) {
    setState(() {
      _exibirCriarJogo = exibir;
    });
  }

  // --- 🛡️ BLINDAGEM DE SAÍDA ---
  Future<bool> _onWillPop() async {
    if (_exibirCriarJogo) {
      _alternarCriacao(false);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: _buildAppBar(),
        
        // Usamos um AnimatedSwitcher para a troca entre lista e criação ser "Master"
        body: IndexedStack(
          index: _abaAtual,
          children: [
            // ABA 0: Lógica de troca com animação suave
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

  // --- 🎨 UI COMPONENTS NIVEL MASTER ---

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: backgroundColor,
      elevation: 0,
      leading: _exibirCriarJogo && _abaAtual == 0
          ? IconButton(
              icon: const Icon(Icons.close, color: Colors.white), // "X" fica mais intuitivo para cancelar criação
              onPressed: () => _alternarCriacao(false),
            )
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Image.asset('assets/logo_icon.png', errorBuilder: (c, e, s) => const Icon(Icons.sports_soccer, color: Color(0xFF00E676))),
            ),
      title: Text(
        _exibirCriarJogo ? "NOVA CONVOCAÇÃO" : "DefendePraMim",
        style: const TextStyle(
          letterSpacing: 1.4,
          fontSize: 24,
          fontWeight: FontWeight.bold, 
          color: Colors.white
        ),
      ),
      centerTitle: true,
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
              onPressed: () {},
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              ),
            )
          ],
        ),
      ],
    );
  }

  Widget? _buildFAB() {
    if (_abaAtual != 0 || _exibirCriarJogo) return null;

    return FloatingActionButton.extended(
      onPressed: () => _alternarCriacao(true),
      backgroundColor: primaryColor,
      elevation: 4,
      // Efeito de "Glow" Neon no botão
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
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _abaAtual,
        onTap: (index) {
          if (_exibirCriarJogo && index != 0) {
            // Opcional: Mostrar um alerta perguntando se deseja descartar o rascunho
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
            icon: Icon(Icons.sports_soccer_rounded), 
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