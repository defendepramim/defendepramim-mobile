import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'card_jogo_contratante.dart';

class AbaMeusJogos extends StatefulWidget {
  const AbaMeusJogos({super.key});

  @override
  State<AbaMeusJogos> createState() => _AbaMeusJogosState();
}

class _AbaMeusJogosState extends State<AbaMeusJogos> {
  final Color primaryColor = const Color(0xFF00E676);
  final Color surfaceColor = const Color(0xFF1E1E1E);

  @override
  Widget build(BuildContext context) {
    // 🟢 AGORA USAMOS O PADRÃO DE ABAS DO GOLEIRO
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text(
            "Minhas Peladas",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          bottom: TabBar(
            indicatorColor: primaryColor,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: "AGENDA"),
              Tab(text: "HISTÓRICO"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAbaAgenda(),
            _buildAbaHistorico(),
          ],
        ),
      ),
    );
  }

  // --- 📅 ABA 1: AGENDA (Apenas o que precisa da atenção do Contratante) ---
  Widget _buildAbaAgenda() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jogos')
          .where('idContratante', isEqualTo: uid)
          .orderBy('dataHora', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Erro ao carregar jogos", style: TextStyle(color: Colors.white)));
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: primaryColor));

        final documentos = snapshot.data?.docs ?? [];
        if (documentos.isEmpty) return _buildEmptyState();

        final agora = DateTime.now();

        // 1. EM DISPUTA (Urgência máxima)
        final contestados = documentos.where((doc) => doc['status'] == 'contestado').toList();
        
        // 2. FINALIZAR E PAGAR (Já passou do horário de término)
        final pendentesAcao = documentos.where((doc) {
          if (doc['status'] != 'fechado') return false;
          final dt = (doc['dataHora'] as Timestamp).toDate();
          final fim = dt.add(Duration(minutes: doc['duracao'] ?? 60));
          return agora.isAfter(fim) || agora.isAtSameMomentAs(fim);
        }).toList();

        // 3. EM ANDAMENTO (Bola rolando AGORA!)
        final emAndamento = documentos.where((doc) {
          if (doc['status'] != 'fechado') return false;
          final dt = (doc['dataHora'] as Timestamp).toDate();
          final fim = dt.add(Duration(minutes: doc['duracao'] ?? 60));
          return agora.isAfter(dt) && agora.isBefore(fim); 
        }).toList();

        // 4. PRÓXIMAS PARTIDAS (Abertas aguardando goleiro ou fechadas no futuro)
        final proximos = documentos.where((doc) {
          final s = doc['status'];
          final dt = (doc['dataHora'] as Timestamp).toDate();
          
          if (s == 'aberto' && agora.isBefore(dt)) return true; // Aberto no futuro
          if (s == 'fechado' && agora.isBefore(dt)) return true; // Fechado no futuro
          
          return false;
        }).toList();

        if (contestados.isEmpty && pendentesAcao.isEmpty && emAndamento.isEmpty && proximos.isEmpty) {
          return _buildEmptyState();
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            const SizedBox(height: 10),

            if (contestados.isNotEmpty) ...[
              _buildHeader(Icons.gavel_rounded, "EM DISPUTA", Colors.redAccent),
              ...contestados.map((doc) => _buildCard(doc, primaryColor)),
            ],

            if (pendentesAcao.isNotEmpty) ...[
              _buildHeader(Icons.priority_high_rounded, "FINALIZAR E PAGAR", Colors.orangeAccent),
              ...pendentesAcao.map((doc) => _buildCard(doc, primaryColor)),
            ],

            if (emAndamento.isNotEmpty) ...[
              _buildHeader(Icons.sports_soccer, "EM ANDAMENTO", const Color(0xFF00E676)),
              ...emAndamento.map((doc) => _buildCard(doc, primaryColor)),
            ],

            if (proximos.isNotEmpty) ...[
              _buildHeader(Icons.calendar_today_rounded, "PRÓXIMAS PARTIDAS", Colors.blueAccent),
              ...proximos.map((doc) => _buildCard(doc, primaryColor)),
            ],
            
            const SizedBox(height: 50),
          ],
        );
      },
    );
  }

  // --- 📚 ABA 2: HISTÓRICO (O que já passou, expirou ou cancelou) ---
  Widget _buildAbaHistorico() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jogos')
          .where('idContratante', isEqualTo: uid)
          .orderBy('dataHora', descending: true) // 🟢 Histórico desce do mais recente pro mais antigo!
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Erro ao carregar jogos", style: TextStyle(color: Colors.white)));
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: primaryColor));

        final agora = DateTime.now();
        final documentos = snapshot.data!.docs;

        final historico = documentos.where((doc) {
          final status = doc['status'];
          final dt = (doc['dataHora'] as Timestamp).toDate();

          // Já finalizados ou cancelados oficialmente vêm pra cá
          if (['finalizado', 'cancelado'].contains(status)) return true;
          
          // 🟢 CORREÇÃO DO BURACO NEGRO: Se está aberto mas o horário do jogo já passou, ele expirou! Vem pro histórico.
          if (status == 'aberto' && agora.isAfter(dt)) return true;

          return false;
        }).toList();

        if (historico.isEmpty) return _buildEmptyState();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            const SizedBox(height: 10),
            _buildHeader(Icons.history_rounded, "HISTÓRICO DE JOGOS", Colors.white54),
            ...historico.map((doc) {
              // Hack Visual: Se caiu no buraco negro, passamos o status como cancelado pro Card entender visualmente!
              Map<String, dynamic> dadosFormatados = Map.from(doc.data() as Map<String, dynamic>);
              dadosFormatados['id'] = doc.id;
              
              final dt = (dadosFormatados['dataHora'] as Timestamp).toDate();
              if (dadosFormatados['status'] == 'aberto' && agora.isAfter(dt)) {
                 dadosFormatados['status'] = 'expirado';
                 dadosFormatados['motivoCancelamento'] = 'O horário passou e nenhum goleiro aceitou.';
              }

              return CardJogoContratante(jogo: dadosFormatados, cor: primaryColor);
            }),
            const SizedBox(height: 50),
          ],
        );
      },
    );
  }

  // --- 🧱 COMPONENTES VISUAIS ---
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sports_soccer, size: 80, color: Colors.white.withAlpha(13)),
          const SizedBox(height: 16),
          const Text(
            "Nenhuma partida encontrada.",
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc, Color cor) {
    final dados = doc.data() as Map<String, dynamic>;
    dados['id'] = doc.id;
    return CardJogoContratante(jogo: dados, cor: cor);
  }

  Widget _buildHeader(IconData icon, String label, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: cor, size: 14),
          const SizedBox(width: 8),
          Text(
            label, 
            style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: cor.withAlpha(26), thickness: 1)),
        ],
      ),
    );
  }
}