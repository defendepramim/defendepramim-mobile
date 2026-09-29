import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'tabs_goleiro/aba_buscar_jogos.dart';
import 'tabs_goleiro/aba_minhas_peladas.dart';
import 'tabs_goleiro/aba_perfil_goleiro.dart';
import 'tabs_goleiro/aba_carteira.dart';

import '../widgets/custom_app_bar.dart';

class HomeGoleiro extends StatefulWidget {
  final int indiceInicial; 

  const HomeGoleiro({super.key, this.indiceInicial = 0}); 

  @override
  State <HomeGoleiro> createState() => _HomeGoleiroState();
}

class _HomeGoleiroState extends State <HomeGoleiro> {
  late int _abaAtual;

  final List _abas = [
    const AbaMinhasPeladas(), 
    const AbaBuscarJogos(),   
    const AbaCarteira(),      
    const AbaPerfilGoleiro(), 
  ];

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(),
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
            icon: Icon(Icons.sports_soccer_outlined), 
            activeIcon: Icon(Icons.sports_soccer),
            label: "Minhas Peladas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search), 
            label: "Buscar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined), 
            activeIcon: Icon(Icons.account_balance_wallet),
            label: "Carteira", 
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline), 
            activeIcon: Icon(Icons.person),
            label: "Perfil",
          ),
        ],
      ),
    );
  }
}