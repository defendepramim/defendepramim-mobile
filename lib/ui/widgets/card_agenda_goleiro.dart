import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defendepramim/ui/screens/tela_chat_jogo.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
// 🟢 IMPORT DO MODAL ADICIONADO AQUI:
import 'package:defendepramim/ui/widgets/modal_perfil_publico.dart';

class CardAgendaGoleiro extends StatelessWidget {
  final String id;
  final Map<String, dynamic> jogo;
  final String cat;
  final String tempoRestante;
  final VoidCallback onAceitarContestacao;
  final VoidCallback onDefenderContestacao;
  final VoidCallback onDesistirPartida;

  const CardAgendaGoleiro({
    super.key,
    required this.id,
    required this.jogo,
    required this.cat,
    required this.tempoRestante,
    required this.onAceitarContestacao,
    required this.onDefenderContestacao,
    required this.onDesistirPartida,
  });

  Future<void> _abrirNoMapaNativo(double lat, double lng) async {
    final Uri uriNativa = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final Uri uriWeb = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    try {
      bool abriuApp = await launchUrl(uriNativa, mode: LaunchMode.externalApplication);
      if (!abriuApp) {
        await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Erro ao abrir mapa nativo: $e");
      launchUrl(uriWeb, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = jogo['status'] ?? '';
    final bool isContestado = status == 'contestado';
    final String statusMediacao = jogo['contestacao']?['statusMediacao'] ?? '';
    final String dataExibicao = jogo['dataExibicao'] ?? '--/--';
    final String horaExibicao = jogo['horaExibicao'] ?? '--:--';

    final String localCompleto = jogo['local'] ?? 'Endereço não informado';
    final String obs = jogo['observacoes']?.toString() ?? ''; 
    
    final List<String> partesLocal = localCompleto.split('(');
    final String nomeQuadra = partesLocal[0].trim();
    final String enderecoRua = partesLocal.length > 1 ? partesLocal[1].replaceAll(')', '').trim() : "Toque no mapa para ver";

    // Pega o nome do contratante para usar no Chat, caso ele exista no jogo
    final String nomeContratante = jogo['nomeContratante'] ?? "Contratante";

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isContestado ? Colors.redAccent.withAlpha(102) : Colors.white.withAlpha(13)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            if (isContestado)
              Container(
                width: double.infinity,
                color: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text("PARTIDA EM CONTESTAÇÃO", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
              ),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(color: const Color(0xFF00E676).withAlpha(13)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("VOCÊ RECEBE", style: TextStyle(color: const Color(0xFF00E676).withAlpha(204), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          // Pega o valor líquido do goleiro (com fallback pro bruto só por segurança)
                          final double valorCalculado = (jogo['valorGoleiro'] ?? jogo['valor'] ?? 0.0).toDouble();
                          // Formata bonitinho com 2 casas decimais e vírgula
                          final String valorFormatado = valorCalculado.toStringAsFixed(2).replaceAll('.', ',');
                          
                          // Renderiza UMA única vez
                          return Text(
                            "R\$ $valorFormatado", 
                            style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: 24)
                          );
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                    // 🟢 FOTO CLICÁVEL DO CONTRATANTE (BUSCA EM TEMPO REAL)
                      if (jogo['idContratante'] != null)
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('usuarios').doc(jogo['idContratante']).get(),
                          builder: (context, snapshot) {
                            String fotoReal = "";
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final dados = snapshot.data!.data() as Map<String, dynamic>;
                              fotoReal = dados['fotoUrl'] ?? "";
                            }
                            
                            return InkWell(
                              onTap: () {
                                ModalPerfilPublico.mostrar(
                                  context,
                                  uid: jogo['idContratante'], 
                                  isGoleiro: false, // Diz ao modal que é um Contratante!
                                );
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white12,
                                backgroundImage: fotoReal.isNotEmpty ? NetworkImage(fotoReal) : null,
                                child: fotoReal.isEmpty ? const Icon(Icons.person, color: Colors.white54, size: 18) : null,
                              ),
                            );
                          },
                        ),
                      const SizedBox(width: 12),

                      // 🚀 BOTÃO DO CHAT AQUI (Disponível sempre que for um card válido)
                      InkWell(
                        onTap: () {
                           Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TelaChatJogo(
                                idJogo: id, 
                                nomeDestinatario: nomeContratante,
                                dataHoraJogo: (jogo['dataHora'] as Timestamp).toDate(),
                                duracaoJogo: (jogo['duracao'] as num?)?.toInt() ?? 60, 
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: EdgeInsets.only(right: (cat == "ao_vivo") ? 8 : 0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E676), size: 20),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('jogos')
                                    .doc(id) 
                                    .collection('mensagens')
                                    .where('lida', isEqualTo: false) 
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return const SizedBox.shrink(); 
                                  }

                                  final uid = FirebaseAuth.instance.currentUser?.uid;
                                  final temMensagemPraMim = snapshot.data!.docs.any((doc) {
                                    final msg = doc.data() as Map<String, dynamic>;
                                    return msg['idRemetente'] != uid;
                                  });

                                  if (temMensagemPraMim) {
                                    return Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFF1E1E1E), width: 1.5),
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Status original
                      if (cat == "ao_vivo") 
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.redAccent.withAlpha(51), borderRadius: BorderRadius.circular(8)),
                          child: const Row(
                            children: [
                              Icon(Icons.sports_soccer, color: Colors.redAccent, size: 14),
                              SizedBox(width: 4),
                              Text("ROLANDO", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                            ],
                          ),
                        )
                    ],
                  )
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.grass_outlined, color: Colors.grey, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nomeQuadra, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(enderecoRua, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                            
                            if (obs.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Tooltip(
                                  message: obs,
                                  triggerMode: TooltipTriggerMode.tap, 
                                  decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(8)),
                                  textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline, color: Colors.white38, size: 12),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          obs,
                                          style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                                          maxLines: 1, 
                                          overflow: TextOverflow.ellipsis, 
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (jogo['latitude'] != null && jogo['longitude'] != null)
                        IconButton(
                          onPressed: () => _abrirNoMapaNativo((jogo['latitude'] as num).toDouble(), (jogo['longitude'] as num).toDouble()),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.blueAccent.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.map_rounded, color: Colors.blueAccent, size: 20),
                          ),
                        )
                    ],
                  ),
                  const SizedBox(height: 15),

                  if (isContestado) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(8), borderRadius: BorderRadius.circular(15)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("O CONTRATANTE ALEGOU:", style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text("${jogo['contestacao']?['motivo']}", style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (statusMediacao == 'aguardando_goleiro')
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onAceitarContestacao,
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white60, side: const BorderSide(color: Colors.white12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              child: const Text("ACEITAR", style: TextStyle(fontSize: 11)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: onDefenderContestacao,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              child: const Text("DEFENDER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    else
                      const Center(child: Text("⏳ EM ANÁLISE PELO SUPORTE", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        _badgeIcone(Icons.calendar_month, "$dataExibicao às $horaExibicao", Colors.white70),
                        _badgeIcone(Icons.access_time, tempoRestante, cat == "ao_vivo" ? const Color(0xFF00E676) : Colors.white70),
                      ],
                    ),
                    if (cat == "agenda") ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onDesistirPartida,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withAlpha(128)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("DESISTIR DA PARTIDA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeIcone(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(51))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}