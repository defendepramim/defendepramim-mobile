import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CardHistoricoGoleiro extends StatelessWidget {
  final Map<String, dynamic> jogo;
  final DateTime agora;

  const CardHistoricoGoleiro({
    super.key,
    required this.jogo,
    required this.agora,
  });

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF00E676);
    const Color surfaceColor = Color(0xFF1E1E1E);

    final DateTime dtAbsoluta = (jogo['dataHora'] as Timestamp).toDate();
    final int duracao = jogo['duracao'] ?? 60;
    
    final String dataExibicao = jogo['dataExibicao'] ?? "${dtAbsoluta.day.toString().padLeft(2, '0')}/${dtAbsoluta.month.toString().padLeft(2, '0')}";
    final String horaExibicao = jogo['horaExibicao'] ?? "${dtAbsoluta.hour.toString().padLeft(2, '0')}:${dtAbsoluta.minute.toString().padLeft(2, '0')}";

    DateTime dataAlvoReal;
    try {
      final partesData = dataExibicao.split('/');
      final partesHora = horaExibicao.split(':');
      dataAlvoReal = DateTime(dtAbsoluta.year, int.parse(partesData[1]), int.parse(partesData[0]), int.parse(partesHora[0]), int.parse(partesHora[1]));
    } catch (e) {
      dataAlvoReal = dtAbsoluta;
    }

    final DateTime fimPartida = dataAlvoReal.add(Duration(minutes: duracao));
    final String status = jogo['status'] ?? '';
    final Map<String, dynamic>? contestacao = jogo['contestacao'] as Map<String, dynamic>?;
    final String statusMediacao = contestacao?['statusMediacao'] ?? '';
    
    final bool isContestacaoAceita = status == 'contestado_aceito' || statusMediacao == 'resolvido_goleiro_aceitou';
    final bool isContestadoPendente = status == 'contestado' && statusMediacao == 'aguardando_goleiro';
    final bool emAnaliseSuporte = statusMediacao == 'em_analise_suporte';
    final bool foiCancelado = status == 'cancelado' && !isContestacaoAceita;
    final bool pendenteLiberacao = status == 'fechado' && agora.isAfter(fimPartida);

    Color corStatus;
    IconData iconeStatus;
    String rotuloStatus;
    String? subTexto;

    if (isContestacaoAceita) {
      corStatus = Colors.purpleAccent; 
      iconeStatus = Icons.assignment_return_rounded;
      rotuloStatus = "CONTESTAÇÃO ACEITA";
      subTexto = "Você aceitou a contestação.";
    } else if (isContestadoPendente || emAnaliseSuporte) {
      corStatus = Colors.orangeAccent;
      iconeStatus = Icons.gavel_rounded;
      rotuloStatus = emAnaliseSuporte ? "EM ANÁLISE" : "CONTESTADO";
      subTexto = emAnaliseSuporte ? "Suporte decidindo..." : "Aguardando sua defesa.";
    } else if (foiCancelado) {
      corStatus = Colors.redAccent;
      iconeStatus = Icons.block_flipped;
      rotuloStatus = "CANCELADO";
      subTexto = "Partida não realizada.";
    } else if (pendenteLiberacao) {
      corStatus = Colors.orangeAccent;
      iconeStatus = Icons.timer_outlined;
      rotuloStatus = "PROCESSANDO";
      final diff = fimPartida.add(const Duration(hours: 12)).difference(agora);
      subTexto = diff.isNegative ? "Liberando saldo..." : "Libera em ${diff.inHours}h ${diff.inMinutes % 60}m";
    } else {
      corStatus = primaryColor;
      iconeStatus = Icons.check_circle_outline;
      rotuloStatus = "CONCLUÍDO";
      subTexto = "$dataExibicao às $horaExibicao";
    }

    final String localCurto = jogo['local'].toString().split('(')[0].trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (isContestacaoAceita || isContestadoPendente) ? corStatus.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: corStatus.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(iconeStatus, color: corStatus, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localCurto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  subTexto,
                  style: TextStyle(color: (isContestacaoAceita || isContestadoPendente) ? corStatus : Colors.white54, fontSize: 11, fontWeight: (isContestacaoAceita || isContestadoPendente) ? FontWeight.bold : FontWeight.normal),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "R\$ ${jogo['valorGoleiro'] ?? jogo['valor']}",
                style: TextStyle(
                  color: (foiCancelado || isContestacaoAceita) ? Colors.white24 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  decoration: (foiCancelado || isContestacaoAceita) ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: corStatus.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(rotuloStatus, style: TextStyle(color: corStatus, fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}