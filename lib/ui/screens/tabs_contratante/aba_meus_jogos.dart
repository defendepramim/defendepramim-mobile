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
  bool _alertaEmExibicao = false;

  // --- O PULO DO GATO: CHECAGEM DE PAGAMENTOS PROCESSADOS PELA CLOUD FUNCTION ---
  void _verificarPagamentosAutomaticos(List<QueryDocumentSnapshot> documentos) {
    // Filtra jogos que a Cloud Function finalizou mas o app ainda não avisou
    final processadosPeloSistema = documentos.where((doc) {
      final dados = doc.data() as Map<String, dynamic>;
      return dados['finalizadoAutomaticamente'] == true && dados['notificadoNoApp'] != true;
    }).toList();

    if (processadosPeloSistema.isNotEmpty && !_alertaEmExibicao) {
      _alertaEmExibicao = true;
      
      // PostFrameCallback garante que o diálogo só abra após o término da construção da tela
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _exibirDialogoInformativo(processadosPeloSistema);
        _alertaEmExibicao = false;
      });
    }
  }

Future<void> _exibirDialogoInformativo(List<QueryDocumentSnapshot> jogos) async {
    // 1. Busca a regra de tempo do Admin antes de mostrar o balão
    int horasRegra = 12; // Valor padrão de segurança
    try {
      final configDoc = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (configDoc.exists && configDoc.data()?['horasPagamentoAuto'] != null) {
        horasRegra = (configDoc.data()?['horasPagamentoAuto'] as num).toInt();
      }
    } catch (e) {
      debugPrint("Erro ao buscar horasPagamentoAuto: $e");
    }

    if (!mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFF00E676)),
            SizedBox(width: 10),
            Text("Pagamento Liberado", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // 🟢 O texto agora usa a variável horasRegra dinamicamente!
              "O prazo de ${horasRegra}h expirou para ${jogos.length} partida(s). O pagamento foi repassado aos goleiros automaticamente:",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 15),
            
            // ✨ AQUI: Criamos uma lista com o nome e horário dos jogos afetados
            ...jogos.map((doc) {
              final dados = doc.data() as Map<String, dynamic>;
              final String local = dados['local'] ?? 'Arena';
              final String dataStr = dados['dataExibicao'] ?? "--/--";
              final String horaStr = dados['horaExibicao'] ?? "--:--";
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "$local • $dataStr às $horaStr", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                      )
                    ),
                  ],
                ),
              );
            }).toList(),
            // -------------------------------------------------------------
            
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final batch = FirebaseFirestore.instance.batch();
              
              for (var doc in jogos) {
                final dados = doc.data() as Map<String, dynamic>;
                final String? idGoleiro = dados['idGoleiro'];
                final String? idContratante = dados['idContratante'];

                // 1. Marca como notificado
                batch.update(doc.reference, {'notificadoNoApp': true});

                // 2. ✨ COMPUTAR NO PERFIL DO GOLEIRO (Atuadas +1)
                if (idGoleiro != null) {
                  batch.update(FirebaseFirestore.instance.collection('usuarios').doc(idGoleiro), {
                    'atuadas': FieldValue.increment(1),
                  });
                }

                // 3. ✨ COMPUTAR NO PERFIL DO CONTRATANTE (Realizados +1)
                if (idContratante != null) {
                  batch.update(FirebaseFirestore.instance.collection('usuarios').doc(idContratante), {
                    'jogosRealizados': FieldValue.increment(1),
                  });
                }
              }
              await batch.commit();
            },
            child: const Text("OK, ENTENDIDO", style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

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
          
          if (documentos.isEmpty) return _buildEmptyState();

          // DISPARA A CHECAGEM AUTOMÁTICA
          _verificarPagamentosAutomaticos(documentos);

          final agora = DateTime.now();

          // --- FILTROS DE CATEGORIA ---
          
          // 1. EM DISPUTA (Urgência máxima)
          final contestados = documentos.where((doc) => doc['status'] == 'contestado').toList();
          
          // 2. FINALIZAR E PAGAR (Já passou do horário de término)
final pendentesAcao = documentos.where((doc) {
  if (doc['status'] != 'fechado') return false;
  final dt = (doc['dataHora'] as Timestamp).toDate();
  final fim = dt.add(Duration(minutes: doc['duracao'] ?? 60));
  return agora.isAfter(fim) || agora.isAtSameMomentAs(fim); // Bola já parou de rolar
}).toList();

// 3. EM ANDAMENTO (Bola rolando AGORA!)
final emAndamento = documentos.where((doc) {
  if (doc['status'] != 'fechado') return false;
  final dt = (doc['dataHora'] as Timestamp).toDate();
  final fim = dt.add(Duration(minutes: doc['duracao'] ?? 60));
  return agora.isAfter(dt) && agora.isBefore(fim); // Passou do início, mas não chegou no fim
}).toList();

// 4. PRÓXIMAS PARTIDAS (Ainda não começou)
final proximos = documentos.where((doc) {
            final s = doc['status'];
            if (['cancelado', 'finalizado', 'contestado'].contains(s)) return false;
            final dt = (doc['dataHora'] as Timestamp).toDate();
            return agora.isBefore(dt);
          }).toList();

          // 🟢 SÓ DEVOLVER ESSA LINHA AQUI (5. HISTÓRICO)
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
          // 🛠️ CORREÇÃO APLICADA: Substituído de .withOpacity(0.05) para .withAlpha(13)
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
      padding: const EdgeInsets.only(top: 25, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: cor, size: 14),
          const SizedBox(width: 8),
          Text(
            label, 
            style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)
          ),
          const SizedBox(width: 10),
          // 🛠️ CORREÇÃO APLICADA: Substituído de .withOpacity(0.1) para .withAlpha(26)
          Expanded(child: Divider(color: cor.withAlpha(26), thickness: 1)),
        ],
      ),
    );
  }
}