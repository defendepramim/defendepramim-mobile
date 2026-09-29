import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:defendepramim/ui/screens/tela_chat_jogo.dart';

class CardHistoricoGoleiro extends StatelessWidget {
  final Map<String, dynamic> jogo;
  final DateTime agora;

  const CardHistoricoGoleiro({
    super.key,
    required this.jogo,
    required this.agora,
  });

  // 💬 LÓGICA DO CHAT: 1 hora após o fim da partida
  bool get _chatAberto {
    final Timestamp? ts = jogo['dataHora'] as Timestamp?;
    if (ts == null) return false;
    
    final dataHoraJogo = ts.toDate();
    final duracaoMin = (jogo['duracao'] as num?)?.toInt() ?? 60;
    
    final fimDaPartida = dataHoraJogo.add(Duration(minutes: duracaoMin));
    final limiteChat = fimDaPartida.add(const Duration(hours: 1));
    
    return agora.isBefore(limiteChat);
  }

  @override
  Widget build(BuildContext context) {
    // 1. Extração de Dados
    final Timestamp? ts = jogo['dataHora'];
    final DateTime dataJogo = ts?.toDate() ?? DateTime.now();
    final int duracao = (jogo['duracao'] as num?)?.toInt() ?? 60;
    final int horasCarencia = (jogo['horasCarencia'] as num?)?.toInt() ?? 24;
    final double valor = (jogo['valorGoleiro'] ?? jogo['valor'] ?? 0.0).toDouble();
    final String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');
    final String status = jogo['status'] ?? '';
    final String localFull = jogo['local'] ?? 'Arena não informada';
    final String nomeContratante = jogo['nomeContratante'] ?? "Contratante";
    final String idJogo = jogo['id']?.toString() ?? '';

    String nomeArena = localFull;
    if (localFull.contains('(')) {
      nomeArena = localFull.split('(')[0].trim();
    }

    // 2. Cálculos de Tempo de Liberação
    final DateTime fimDaPartida = dataJogo.add(Duration(minutes: duracao));
    DateTime dataLiberacao = jogo['dataLiberacaoPagamento'] != null
        ? (jogo['dataLiberacaoPagamento'] as Timestamp).toDate()
        : fimDaPartida.add(Duration(hours: horasCarencia));

    final Duration tempoParaLiberar = dataLiberacao.difference(agora);
    final bool aindaEmCarencia = tempoParaLiberar.inSeconds > 0;

    // 3. Estilização Dinâmica
    Color corDestaque = Colors.grey;
    IconData icone = Icons.sports_soccer;
    String tagTexto = "";
    Color corTag = Colors.grey;

    if (status == 'cancelado') {
      corDestaque = Colors.redAccent;
      icone = Icons.block;
      tagTexto = "CANCELADO";
      corTag = Colors.redAccent;
    } else if (status == 'contestado' || status == 'contestado_aceito') {
      corDestaque = Colors.orangeAccent;
      icone = Icons.warning_amber_rounded;
      tagTexto = "EM DISPUTA";
      corTag = Colors.orangeAccent;
    } else if (status == 'concluido' || status == 'finalizado') {
      corDestaque = const Color(0xFF00E676);
      icone = Icons.check_circle_rounded;
      tagTexto = "PAGO";
      corTag = const Color(0xFF00E676);
    } else if (status == 'fechado') {
      corDestaque = Colors.orangeAccent;
      icone = Icons.timer_outlined;
      if (aindaEmCarencia) {
        final int horas = tempoParaLiberar.inHours;
        final int minutos = tempoParaLiberar.inMinutes.remainder(60);
        tagTexto = "LIBERA EM ${horas}h ${minutos}m";
        corTag = Colors.orangeAccent;
      } else {
        tagTexto = "PROCESSANDO";
        corTag = Colors.orangeAccent;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corDestaque.withAlpha(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Ícone Circular
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: corDestaque.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: corDestaque, size: 20),
              ),
              const SizedBox(width: 12),
              
              // Informações Principais
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeArena.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${DateFormat('dd/MM').format(dataJogo)} às ${DateFormat('HH:mm').format(dataJogo)} • $nomeContratante",
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Valor + Tag de Status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "+ R\$ $valorFormatado",
                    style: TextStyle(color: corDestaque, fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: corTag.withAlpha(26),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tagTexto,
                      style: TextStyle(
                        color: corTag,
                        fontWeight: FontWeight.w900,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 💬 BARRINHA DE AÇÃO RÁPIDA (CHAT)
          if (idJogo.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white10, height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _chatAberto ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                      size: 12,
                      color: _chatAberto ? const Color(0xFF00E676) : Colors.white24,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _chatAberto ? "Chat pós-jogo liberado" : "Chat encerrado",
                      style: TextStyle(
                        color: _chatAberto ? const Color(0xFF00E676) : Colors.white24,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                
                // Botão Bate-Papo
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TelaChatJogo(
                          idJogo: idJogo,
                          nomeDestinatario: nomeContratante,
                          dataHoraJogo: dataJogo,
                          duracaoJogo: duracao,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _chatAberto ? const Color(0xFF00E676).withAlpha(25) : Colors.white.withAlpha(8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _chatAberto ? const Color(0xFF00E676).withAlpha(60) : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 13,
                              color: _chatAberto ? const Color(0xFF00E676) : Colors.white38,
                            ),
                            // Stream de alerta de mensagem nova
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('jogos')
                                  .doc(idJogo)
                                  .collection('mensagens')
                                  .orderBy('dataEnvio', descending: true)
                                  .limit(1)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                final ultimaMsg = snapshot.data!.docs.first.data() as Map<String, dynamic>;

                                if (ultimaMsg['idRemetente'] != uid && (ultimaMsg['lida'] == false || ultimaMsg['lida'] == null)) {
                                  return Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "CONVERSA",
                          style: TextStyle(
                            color: _chatAberto ? const Color(0xFF00E676) : Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}