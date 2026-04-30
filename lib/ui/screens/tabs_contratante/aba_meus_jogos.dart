import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'card_jogo_contratante.dart';

class AbaMeusJogos extends StatelessWidget {
  const AbaMeusJogos({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    const primaryColor = Color(0xFF00E676);

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jogos')
            .where('idContratante', isEqualTo: uid)
            .orderBy('dataHora', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Erro ao carregar jogos", style: TextStyle(color: Colors.white)));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final documentos = snapshot.data?.docs ?? [];
          
          if (documentos.isEmpty) {
            return _buildEmptyState();
          }

          final agora = DateTime.now(); // Idealmente usar a hora sincronizada do servidor

          // 1. EM DISPUTA (Urgência máxima)
          final contestados = documentos.where((doc) => doc['status'] == 'contestado').toList();
          
          // 2. PAGAMENTOS PENDENTES (Jogos que já acabaram mas não foram finalizados/pagos)
          final pendentesAcao = documentos.where((doc) {
            if (doc['status'] != 'fechado') return false;
            final dt = (doc['dataHora'] as Timestamp).toDate();
            final fim = dt.add(Duration(minutes: doc['duracao'] ?? 60));
            return agora.isAfter(fim);
          }).toList();

          // 3. PRÓXIMAS PARTIDAS (Abertas ou Fechadas que ainda vão acontecer)
          final proximos = documentos.where((doc) {
            final s = doc['status'];
            if (['cancelado', 'finalizado', 'contestado'].contains(s)) return false;
            final dt = (doc['dataHora'] as Timestamp).toDate();
            // Jogo ainda não acabou
            return agora.isBefore(dt.add(Duration(minutes: doc['duracao'] ?? 60)));
          }).toList();

          // 4. HISTÓRICO (Finalizados e Cancelados)
          final historico = documentos.where((doc) => 
            ['finalizado', 'cancelado'].contains(doc['status'])).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              const SizedBox(height: 40),
              const Text(
                "Minhas Partidas", 
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -1)
              ),
              const SizedBox(height: 20),

              if (contestados.isNotEmpty) ...[
                _buildHeader(Icons.gavel_rounded, "EM DISPUTA", Colors.redAccent),
                ...contestados.map((doc) => _buildCard(doc, primaryColor)),
              ],

              if (pendentesAcao.isNotEmpty) ...[
                _buildHeader(Icons.priority_high_rounded, "FINALIZAR E PAGAR", Colors.orangeAccent),
                ...pendentesAcao.map((doc) => _buildCard(doc, primaryColor)),
              ],

              if (proximos.isNotEmpty) ...[
                _buildHeader(Icons.calendar_today_rounded, "PRÓXIMAS PARTIDAS", Colors.blueAccent),
                ...proximos.map((doc) => _buildCard(doc, primaryColor)),
              ],

              if (historico.isNotEmpty) ...[
                _buildHeader(Icons.history_rounded, "HISTÓRICO", Colors.white24),
                ...historico.map((doc) => _buildCard(doc, primaryColor)),
              ],
              
              const SizedBox(height: 50),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sports_soccer, size: 80, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 16),
          const Text(
            "Você não criou nenhuma pelada.",
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot doc, Color cor) {
    final dados = doc.data() as Map<String, dynamic>;
    dados['id'] = doc.id; // Garante que o Card saiba o ID do documento para dar update
    return CardJogoContratante(jogo: dados, cor: cor);
  }

  Widget _buildHeader(IconData icon, String label, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(top: 25, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: cor, size: 14),
          const SizedBox(width: 8),
          Text(
            label, 
            style: TextStyle(
              color: cor, 
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 1.2
            )
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: cor.withOpacity(0.1), thickness: 1)),
        ],
      ),
    );
  }
}