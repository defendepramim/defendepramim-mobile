import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// 🟢 NÃO ESQUEÇA DE IMPORTAR O CARD QUE ACABAMOS DE MELHORAR!
import 'package:defendepramim/ui/widgets/card_historico_goleiro.dart';

class TelaHistoricoGoleiro extends StatefulWidget {
  const TelaHistoricoGoleiro({super.key});

  @override
  State<TelaHistoricoGoleiro> createState() => _TelaHistoricoGoleiroState();
}

class _TelaHistoricoGoleiroState extends State<TelaHistoricoGoleiro> {
  DateTimeRange? _periodo;
  final String? uid = FirebaseAuth.instance.currentUser?.uid;
  final Color primaryColor = const Color(0xFF00E676);

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _periodo = DateTimeRange(
      start: DateTime(agora.year, agora.month, 1),
      end: DateTime(agora.year, agora.month, agora.day, 23, 59),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context), 
        ),
        title: const Text("Histórico de Ganhos", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            onPressed: _selecionarDatas,
            icon: Icon(Icons.tune, color: primaryColor),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('jogos')
            .where('idGoleiro', isEqualTo: uid)
            .where('status', isEqualTo: 'finalizado')
            .where('dataHora', isGreaterThanOrEqualTo: _periodo!.start)
            .where('dataHora', isLessThanOrEqualTo: _periodo!.end)
            .orderBy('dataHora', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)));
          }
          
          final docs = snapshot.data?.docs ?? [];
          double totalGanhos = 0.0;
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            // 🟢 Pega o valor líquido do goleiro (com fallback seguro)
            final valorRaw = data['valorPagoAoGoleiro'] ?? data['valorGoleiro'] ?? data['valor'];
            if (valorRaw is num) totalGanhos += valorRaw.toDouble();
            else if (valorRaw is String) totalGanhos += double.tryParse(valorRaw) ?? 0.0;
          }

          return Column(
            children: [
              _buildResumoCard(totalGanhos, docs.length),
              
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("DETALHAMENTO", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: docs.isEmpty 
                  ? _buildEmptyState() 
                  : ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final jogo = docs[index].data() as Map<String, dynamic>;
                        
                        // 🟢 AGORA USAMOS O MESMO CARD PREMIUM AQUI TAMBÉM!
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: CardHistoricoGoleiro(
                            jogo: jogo,
                            agora: DateTime.now(),
                          ),
                        );
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResumoCard(double total, int qtd) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Text("TOTAL FATURADO NO PERÍODO", 
            style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            "R\$ ${total.toStringAsFixed(2).replaceAll('.', ',')}", 
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1), 
              borderRadius: BorderRadius.circular(20)
            ),
            child: Text("$qtd Partidas Realizadas", 
              style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today, color: Colors.white38, size: 14),
              const SizedBox(width: 8),
              Text(
                "${DateFormat('dd/MM').format(_periodo!.start)} até ${DateFormat('dd/MM').format(_periodo!.end)}",
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history_toggle_off, color: Colors.white10, size: 64),
        SizedBox(height: 16),
        Text("Nenhum registro encontrado no período.", style: TextStyle(color: Colors.white24)),
      ],
    );
  }

  Future<void> _selecionarDatas() async {
    final novoPeriodo = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _periodo,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: primaryColor, 
              onPrimary: Colors.black, 
              surface: const Color(0xFF1E1E1E)
            ),
          ),
          child: child!,
        );
      },
    );
    if (novoPeriodo != null) setState(() => _periodo = novoPeriodo);
  }
}