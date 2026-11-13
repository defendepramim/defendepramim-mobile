import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ModalPerfilPublico extends StatelessWidget {
  final String uid;
  final bool isGoleiro;

  const ModalPerfilPublico({
    super.key,
    required this.uid,
    required this.isGoleiro,
  });

  static void mostrar(BuildContext context, {required String uid, required bool isGoleiro}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModalPerfilPublico(uid: uid, isGoleiro: isGoleiro),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      // 🟢 BUSCA OS DADOS (O ROBÔ JÁ FEZ A MATEMÁTICA LÁ NO SERVIDOR)
      child: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('usuarios').doc(uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final nome = data['nome'] ?? (isGoleiro ? "Goleiro" : "Contratante");
          final fotoUrl = data['fotoUrl'] ?? "";
          
          // 🟢 PEGANDO A CATEGORIA OFICIAL CALCULADA PELO INDEX.JS
          final String nivelOficial = data['categoria']?.toString().toUpperCase() ?? "VÁRZEA";
          
          // Estatísticas do Goleiro
          final int atuadas = (data['atuadas'] as num?)?.toInt() ?? 0;
          final int totalAvaliacoes = (data['totalAvaliacoes'] as num?)?.toInt() ?? 0;
          final double somaAvaliacoes = (data['somaAvaliacoes'] as num?)?.toDouble() ?? 0.0;
          final double media = totalAvaliacoes > 0 ? (somaAvaliacoes / totalAvaliacoes) : 0.0;
          
          // Estatísticas do Contratante
          final int partidasOrganizadas = (data['partidasOrganizadas'] as num?)?.toInt() ?? 0;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 24),
              
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white12,
                backgroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
                child: fotoUrl.isEmpty ? const Icon(Icons.person, size: 50, color: Colors.white54) : null,
              ),
              const SizedBox(height: 16),
              
              Text(nome, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(isGoleiro ? "Goleiro" : "Organizador da Pelada", style: const TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center),
              
              // 🟢 ETIQUETA COM O NÍVEL OFICIAL DO GOLEIRO
              if (isGoleiro) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withAlpha(26),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00E676).withAlpha(128)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium, color: Color(0xFF00E676), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        "NÍVEL $nivelOficial", 
                        style: const TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // 📊 CAIXA DE ESTATÍSTICAS
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (isGoleiro) ...[
                      _buildStatItem(Icons.sports_soccer, atuadas.toString(), "Partidas"),
                      Container(width: 1, height: 40, color: Colors.white10),
                      _buildStatItem(Icons.star_rounded, totalAvaliacoes > 0 ? media.toStringAsFixed(1) : "Novo", "Avaliação", corIcone: Colors.amber),
                    ] else ...[
                      _buildStatItem(Icons.stadium_outlined, partidasOrganizadas.toString(), "Jogos Organizados"),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String valor, String label, {Color corIcone = const Color(0xFF00E676)}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: corIcone, size: 18),
            const SizedBox(width: 6),
            Text(valor, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}