import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AbaCarteira extends StatelessWidget {
  const AbaCarteira({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    const primaryColor = Color(0xFF00E676);
    const backgroundColor = Colors.black;

    if (uid == null) return const Center(child: Text("Usuário não logado"));

    return Scaffold(
      backgroundColor: backgroundColor,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .collection('extrato')
            .orderBy('data', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(
              child: Text(
                "Erro ao carregar",
                style: TextStyle(color: Colors.white),
              ),
            );
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          final documentos = snapshot.data?.docs ?? [];

          double entradasConcluidas = 0;
          double saidasReais = 0;
          double valorRetidoContestacao = 0;
          double dividasDeMultas = 0;

          // --- LÓGICA DE CÁLCULO ---
          for (var doc in documentos) {
            final dados = doc.data() as Map<String, dynamic>;
            final valor =
                double.tryParse(dados['valor']?.toString() ?? '0') ?? 0.0;
            final tipo = dados['tipo'];
            final statusTransacao = dados['status'] ?? 'concluido';

            if (statusTransacao == 'contestado') {
              valorRetidoContestacao += valor;
            } else {
              if (tipo == 'recebimento' || tipo == 'entrada') {
                entradasConcluidas += valor;
              } else if (tipo == 'multa_desistencia') {
                dividasDeMultas += valor;
              } else if (tipo == 'saida') {
                saidasReais += valor;
              }
            }
          }

          // Cálculo do saldo com abatimento de multas
          double saldoBruto =
              entradasConcluidas - saidasReais - dividasDeMultas;
          double saldoDisponivelParaSaque = saldoBruto > 0 ? saldoBruto : 0;
          double dividaExibicao = saldoBruto < 0 ? saldoBruto.abs() : 0;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            children: [
              const Text(
                "Minha Carteira",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // 1. CARD PRINCIPAL
              _cardSaldoGoleiro(
                context,
                saldoDisponivelParaSaque,
                primaryColor,
              ),

              const SizedBox(height: 12),

              // 2. LINHA DE ALERTAS (RETIDO E DEVEDOR)
              if (valorRetidoContestacao > 0 || dividaExibicao > 0)
                Row(
                  children: [
                    if (valorRetidoContestacao > 0)
                      Expanded(
                        child: _cardStatusEspecial(
                          "VALOR RETIDO",
                          valorRetidoContestacao,
                          Icons.lock_clock,
                          Colors.orangeAccent,
                        ),
                      ),
                    if (valorRetidoContestacao > 0 && dividaExibicao > 0)
                      const SizedBox(width: 10),
                    if (dividaExibicao > 0)
                      Expanded(
                        child: _cardStatusEspecial(
                          "SALDO DEVEDOR",
                          dividaExibicao,
                          Icons.gavel_rounded,
                          Colors.redAccent,
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 35),
              const Text(
                "Histórico de Transações",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(color: Colors.white10),

              if (documentos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    "Nenhuma movimentação.",
                    style: TextStyle(color: Colors.white24),
                    textAlign: TextAlign.center,
                  ),
                ),

              ...documentos.map((doc) {
                final item = doc.data() as Map<String, dynamic>;
                final tipo = item['tipo'] ?? '';
                final data =
                    (item['data'] as Timestamp?)?.toDate() ?? DateTime.now();
                final valor = item['valor'] ?? 0;
                final status = item['status'] ?? 'concluido';

                if (tipo == 'multa_desistencia') {
                  return _buildItemMulta(
                    item['descricao'] ?? 'Multa',
                    data,
                    valor,
                  );
                }

                return _buildItemHistoricoGoleiro(
                  item['descricao'] ?? 'Partida',
                  data,
                  valor,
                  status == 'contestado' ? Colors.orangeAccent : primaryColor,
                  item['metodo'] ?? 'manual',
                  status,
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }

  // --- WIDGETS DE SUPORTE (FORA DO BUILD) ---

  Widget _cardSaldoGoleiro(BuildContext context, double saldo, Color primary) {
    bool temSaldo = saldo > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        // CORES IGUAIS À DO CONTRATANTE
        gradient: LinearGradient(
          colors: [primary.withOpacity(0.2), Colors.white.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SALDO DISPONÍVEL",
                style: TextStyle(
                  color: primary.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(
                Icons.account_balance_wallet_outlined,
                color: primary.withOpacity(0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "R\$ ${saldo.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              // Só habilita o clique se tiver saldo
              onPressed: temSaldo
                  ? () {
                      /* Sua lógica de saque aqui */
                    }
                  : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: temSaldo ? Colors.black : Colors.white24,
              ),
              label: Text(
                "SOLICITAR SAQUE",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: temSaldo ? Colors.black : Colors.white24,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                // Cor quando o botão está desativado (sem saldo)
                disabledBackgroundColor: Colors.white.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardStatusEspecial(
    String titulo,
    double valor,
    IconData icone,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 14),
              const SizedBox(width: 5),
              Text(
                titulo,
                style: TextStyle(
                  color: cor,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            "R\$ ${valor.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemHistoricoGoleiro(
    String local,
    DateTime data,
    dynamic valor,
    Color cor,
    String metodo,
    String status,
  ) {
    bool isContestado = status == 'contestado';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isContestado ? Icons.lock_outline : Icons.add,
          color: cor,
          size: 18,
        ),
      ),
      title: Text(
        local,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        "${data.day}/${data.month} • ${isContestado ? 'Bloqueado (Contestação)' : 'Crédito liberado'}",
        style: TextStyle(
          color: isContestado
              ? Colors.orangeAccent.withOpacity(0.7)
              : Colors.white38,
          fontSize: 11,
        ),
      ),
      trailing: Text(
        "+ R\$ $valor",
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _buildItemMulta(String desc, DateTime data, dynamic valor) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.remove, color: Colors.redAccent, size: 18),
      ),
      title: Text(
        desc,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        "${data.day}/${data.month} • Multa aplicada",
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Text(
        "- R\$ $valor",
        style: const TextStyle(
          color: Colors.redAccent,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}
