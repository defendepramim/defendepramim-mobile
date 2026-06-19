import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AbaFinanceiroContratante extends StatelessWidget {
  const AbaFinanceiroContratante({super.key});

  Future<void> _adicionarSaldoTeste(BuildContext context) async {
    final TextEditingController valorRecargaController = TextEditingController();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Recarga de Teste", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: valorRecargaController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            prefixText: "R\$ ",
            prefixStyle: const TextStyle(color: Color(0xFF00E676)),
            labelText: "Valor da Recarga",
            labelStyle: const TextStyle(color: Colors.grey),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00E676))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              double valor = double.tryParse(valorRecargaController.text.replaceAll(',', '.')) ?? 0;
              if (valor <= 0 || uid == null) return;

              final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
              final extratoRef = userRef.collection('extrato').doc();
              
              try {
                await FirebaseFirestore.instance.runTransaction((transaction) async {
                  DocumentSnapshot userSnap = await transaction.get(userRef);
                  double saldoAtual = (userSnap.get('saldo') ?? 0.0).toDouble();
                  double novoSaldo = saldoAtual + valor;

                  transaction.update(userRef, {'saldo': novoSaldo});

                  transaction.set(extratoRef, {
                    'id': extratoRef.id,
                    'tipo': 'entrada',
                    'descricao': 'Recarga de Saldo (Teste)',
                    'valor': valor,
                    'saldoAnterior': saldoAtual,
                    'saldoAtual': novoSaldo, 
                    'data': FieldValue.serverTimestamp(),
                    'categoria': 'recarga'
                  });
                });
              } catch (e) {
                print("Erro na transação: $e");
              }

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("CONFIRMAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    const primaryColor = Color(0xFF00E676);

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
        builder: (context, userSnapshot) {
          double saldoReal = 0.0;
          if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final dadosUser = userSnapshot.data!.data() as Map<String, dynamic>;
            saldoReal = (dadosUser['saldo'] ?? 0.0).toDouble();
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Minha Carteira", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                      const SizedBox(height: 20),
                      _cardSaldo(context, saldoReal, primaryColor),
                      const SizedBox(height: 30),
                      const Text("Movimentações", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .collection('extrato')
                    .orderBy('data', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: primaryColor)));
                  }
                  
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                      return _buildEmptyState(); 
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildItemExtrato(data, primaryColor),
                        );
                      },
                      childCount: docs.length,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cardSaldo(BuildContext context, double saldo, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [primary.withAlpha(51), Colors.white.withAlpha(13)], 
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(26)), 
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("SALDO TOTAL", style: TextStyle(color: primary.withAlpha(204), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)), 
              Icon(Icons.account_balance_wallet_outlined, color: primary.withAlpha(128)), 
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "R\$ ${saldo.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _adicionarSaldoTeste(context),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text("ADICIONAR SALDO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemExtrato(Map<String, dynamic> data, Color primary) {
    final String tipo = data['tipo'] ?? 'saida';
    final double valor = (data['valor'] ?? 0.0).toDouble();
    
    IconData icon;
    Color color;
    String prefix;

    if (tipo == 'entrada' || tipo == 'estorno') {
      icon = Icons.add_circle_outline;
      color = primary;
      prefix = "+";
    } else if (tipo == 'multa_cancelamento') {
      icon = Icons.gavel_rounded;
      color = Colors.orangeAccent;
      prefix = "-";
    } else {
      icon = Icons.remove_circle_outline;
      color = Colors.redAccent;
      prefix = "-";
    }

    final DateTime dt = (data['data'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    String dataFormatada = "$dia/$mes às $hora:$minuto";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // 🟢 Alinhamento pro topo para textos grandes não empurrarem o ícone
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle), 
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🟢 maxLines removido para o texto poder crescer para a linha de baixo sem cortar
                Text(
                  data['descricao'] ?? "Transação", 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, height: 1.2),
                ),
                const SizedBox(height: 6),
                Text(dataFormatada, style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2), // Alinha o valor com a primeira linha do título
            child: Text(
              "$prefix R\$ ${valor.toStringAsFixed(2)}",
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8), 
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 60,
                color: Colors.white.withAlpha(26), 
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "NENHUMA MOVIMENTAÇÃO",
              style: TextStyle(
                color: Colors.white.withAlpha(51), 
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Suas entradas e saídas aparecerão aqui.",
              style: TextStyle(
                color: Colors.white.withAlpha(26), 
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}