import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; // 🟢 INJETADO AQUI
import 'tabs_goleiro/aba_buscar_jogos.dart';
import 'tabs_goleiro/aba_minhas_peladas.dart';
import 'tabs_goleiro/aba_perfil_goleiro.dart';
import 'tabs_goleiro/aba_carteira.dart';

class HomeGoleiro extends StatefulWidget {
  const HomeGoleiro({super.key});

  @override
  State<HomeGoleiro> createState() => _HomeGoleiroState();
}

class _HomeGoleiroState extends State<HomeGoleiro> {
  int _abaAtual = 0;

  final List<Widget> _abas = [
    const AbaMinhasPeladas(), 
    const AbaBuscarJogos(),   
    const AbaCarteira(),      
    const AbaPerfilGoleiro(), 
  ];

  // 🟢 MAGIA DAS PERMISSÕES: Roda assim que a tela nasce!
  @override
  void initState() {
    super.initState();
    _solicitarPermissoesEssenciais();
  }

  Future<void> _solicitarPermissoesEssenciais() async {
    // Pede permissão para avisar o goleiro sobre novas convocações ou aprovações
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // Pede localização para o goleiro buscar jogos próximos a ele
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- O TOPO PADRONIZADO ENTRA AQUI ---
      appBar: AppBar(
        // Como o seu tema usa 0xFF121212, vamos manter aqui para casar perfeito
        backgroundColor: const Color(0xFF121212), 
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Defende Pra Mim",
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            color: Colors.white, 
            fontSize: 18
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      // -------------------------------------

      body: _abas[_abaAtual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _abaAtual,
        onTap: (index) => setState(() => _abaAtual = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFF00E676),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer), 
            label: "Minhas Peladas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search), 
            label: "Buscar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet), 
            label: "Carteira", 
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person), 
            label: "Perfil",
          ),
        ],
      ),
    );
  }
}