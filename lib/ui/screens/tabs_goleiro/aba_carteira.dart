import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:defendepramim/ui/widgets/modal_cadastro_pix.dart';

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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) return const Center(child: Text("Erro ao carregar perfil", style: TextStyle(color: Colors.white)));
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryColor));
          }

          final userDados = userSnapshot.data?.data() as Map<String, dynamic>?;
          
          double saldoDisponivelParaSaque = double.tryParse(userDados?['saldo']?.toString() ?? '0') ?? 0.0;
          double valorRetidoContestacao = double.tryParse(userDados?['valorRetido']?.toString() ?? '0') ?? 0.0;
          double dividaExibicao = double.tryParse(userDados?['saldoDevedor']?.toString() ?? '0') ?? 0.0;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .collection('extrato')
                .orderBy('data', descending: true)
                .snapshots(),
            builder: (context, extratoSnapshot) {
              final documentos = extratoSnapshot.data?.docs ?? [];

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                children: [
                  const Text(
                    "Minha Carteira",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 20),

                  // 1. CARD PRINCIPAL
                  _cardSaldoGoleiro(context, uid, saldoDisponivelParaSaque, primaryColor),
                  const SizedBox(height: 12),

                  // 2. LINHA DE ALERTAS (RETIDO E DEVEDOR)
                  if (valorRetidoContestacao > 0 || dividaExibicao > 0)
                    Row(
                      children: [
                        if (valorRetidoContestacao > 0)
                          Expanded(
                            child: _cardStatusEspecial("VALOR RETIDO", valorRetidoContestacao, Icons.lock_clock, Colors.orangeAccent),
                          ),
                        if (valorRetidoContestacao > 0 && dividaExibicao > 0)
                          const SizedBox(width: 10),
                        if (dividaExibicao > 0)
                          Expanded(
                            child: _cardStatusEspecial("SALDO DEVEDOR", dividaExibicao, Icons.gavel_rounded, Colors.redAccent),
                          ),
                      ],
                    ),

                  const SizedBox(height: 35),
                  const Text(
                    "Histórico de Transações",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(color: Color(0xFF1A1A1A)), 

                  if (documentos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text(
                        "Nenhuma movimentação.",
                        style: TextStyle(color: Color(0xFF444444)), 
                        textAlign: TextAlign.center,
                      ),
                    ),

                  ...documentos.map((doc) {
                    final item = doc.data() as Map<String, dynamic>;
                    final tipo = item['tipo'] ?? '';
                    final data = (item['data'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final valor = double.tryParse(item['valor']?.toString() ?? '0') ?? 0.0;
                    final status = item['status'] ?? 'concluido';

                    if (tipo == 'multa_desistencia') {
                      return _buildItemMulta(item['descricao'] ?? 'Multa', data, valor);
                    }

                    return _buildItemHistoricoGoleiro(
                      item['descricao'] ?? 'Transação',
                      data,
                      valor,
                      status == 'contestado' ? Colors.orangeAccent : (tipo == 'saida' ? Colors.redAccent : primaryColor),
                      status,
                      tipo == 'saida',
                      primaryColor,
                    );
                  }).toList(),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --- WIDGETS DE SUPORTE 100% LIMPOS DE WITHOPACITY ---

  Widget _cardSaldoGoleiro(BuildContext context, String uid, double saldo, Color primary) {
    bool temSaldo = saldo > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF0D1F14), 
        border: Border.all(color: const Color(0xFF1A3324)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "SALDO DISPONÍVEL",
                style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
              ),
              Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF00C853), 
              ),
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
              onPressed: temSaldo ? () => _iniciarFluxoSaque(context, uid, saldo, primary) : null,
              icon: Icon(Icons.arrow_upward_rounded, size: 20, color: temSaldo ? Colors.black : const Color(0xFF555555)),
              label: Text(
                "SOLICITAR SAQUE",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: temSaldo ? Colors.black : const Color(0xFF555555)),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                disabledBackgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _iniciarFluxoSaque(BuildContext context, String uid, double saldoDisponivel, Color primary) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
    );

    try {
      final snap = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final dados = snap.data();

      if (!context.mounted) return;
      Navigator.pop(context);

      final chavePix = dados?['chavePix'];
      final tipoPix = dados?['tipoPix'];
      final nomeGoleiro = dados?['nome'] ?? "Goleiro";

      if (chavePix == null || chavePix.toString().trim().isEmpty) {
        _mostrarAlertaPixAusente(context, primary);
        return;
      }

      _abrirModalDigitacaoSaque(context, uid, nomeGoleiro, chavePix.toString(), tipoPix.toString(), saldoDisponivel, primary);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao verificar PIX: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  // 🟢 AQUI ESTÁ A FUNÇÃO DA TRANSAÇÃO INTEIRA DE VOLTA!
  void _abrirModalDigitacaoSaque(
    BuildContext context,
    String uid,
    String nomeGoleiro,
    String chavePix,
    String tipoPix,
    double saldoMaximo,
    Color primary,
  ) {
    final TextEditingController valorController = TextEditingController();
    bool processando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          // 🟢 1. Pega a altura exata da barra do Android do celular do usuário
          final bottomPadding = MediaQuery.of(ctx).padding.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              // 🟢 2. Removemos o const EdgeInsets.all(24) e colocamos esse:
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: 24 + bottomPadding, // 🟢 Empurra o conteúdo para cima da barra!
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // ... (o resto da coluna continua igual)
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "VALOR DO SAQUE",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Disponível: R\$ ${saldoMaximo.toStringAsFixed(2)}\nPIX: $chavePix ($tipoPix)",
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixText: "R\$ ",
                      prefixStyle: const TextStyle(color: Colors.white54, fontSize: 24),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      suffixIcon: TextButton(
                        onPressed: () {
                          setStateSB(() {
                            valorController.text = saldoMaximo.toStringAsFixed(2);
                          });
                        },
                        child: Text("TUDO", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: processando
                          ? null
                          : () async {
                              String textoValor = valorController.text.replaceAll(',', '.');
                              double? valorSaque = double.tryParse(textoValor);

                              if (valorSaque == null || valorSaque <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Digite um valor válido!"), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }

                              if (valorSaque > saldoMaximo) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Saldo insuficiente para este valor."), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }

                              setStateSB(() => processando = true);

                              try {
                                final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
                                final extratoRef = userRef.collection('extrato').doc();
                                final saqueRef = FirebaseFirestore.instance.collection('saques').doc();

                                await FirebaseFirestore.instance.runTransaction((transaction) async {
                                  DocumentSnapshot userSnap = await transaction.get(userRef);
                                  double saldoAtual = (userSnap.data() as Map<String, dynamic>?)?['saldo']?.toDouble() ?? 0.0;

                                  if (saldoAtual < valorSaque) {
                                    throw Exception("Saldo atualizado no servidor é insuficiente.");
                                  }

                                  double novoSaldo = saldoAtual - valorSaque;

                                  transaction.update(userRef, {'saldo': novoSaldo});

                                  transaction.set(extratoRef, {
                                    'id': extratoRef.id,
                                    'idUsuario': uid,
                                    'tipo': 'saida',
                                    'categoria': 'saque',
                                    'valor': valorSaque,
                                    'saldoAnterior': saldoAtual,
                                    'saldoAtual': novoSaldo,
                                    'descricao': 'Saque solicitado',
                                    'status': 'pendente',
                                    'data': FieldValue.serverTimestamp(),
                                  });

                                  transaction.set(saqueRef, {
                                    'id': saqueRef.id,
                                    'idGoleiro': uid,
                                    'nomeGoleiro': nomeGoleiro,
                                    'valor': valorSaque,
                                    'chavePix': chavePix,
                                    'tipoPix': tipoPix,
                                    'status': 'pendente',
                                    'idExtrato': extratoRef.id,
                                    'dataSolicitacao': FieldValue.serverTimestamp(),
                                  });
                                });

                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Saque solicitado com sucesso!"),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                setStateSB(() => processando = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                      child: processando
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text("CONFIRMAR SAQUE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _mostrarAlertaPixAusente(BuildContext context, Color primary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text("PIX não cadastrado", style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          "Para realizar saques, você precisa cadastrar sua Chave PIX primeiro.\n\nQuer fazer isso agora?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("DEPOIS", style: TextStyle(color: Color(0xFF666666))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primary),
            onPressed: () {
              Navigator.pop(ctx);
              ModalCadastroPix.show(context); 
            },
            child: const Text("CADASTRAR PIX", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _cardStatusEspecial(String titulo, double valor, IconData icone, Color cor) {
    final Color corBorda = cor == Colors.orangeAccent ? const Color(0xFF4D3300) : const Color(0xFF4D1A1A);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: corBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 14),
              const SizedBox(width: 5),
              Text(titulo, style: TextStyle(color: cor, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 5),
          Text("R\$ ${valor.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildItemHistoricoGoleiro(String local, DateTime data, double valor, Color cor, String status, bool isSaida, Color primaryColor) {
    bool isContestado = status == 'contestado';
    bool isPendente = status == 'pendente';
    IconData iconeLista = isContestado ? Icons.lock_outline : (isSaida ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);
    String sinalOperacao = isSaida ? "- R\$" : "+ R\$";
    
    String textoBadge = "CONCLUÍDO";
    Color corBadge = primaryColor; 
    
    if (isContestado) {
      textoBadge = "BLOQUEADO";
      corBadge = Colors.orangeAccent;
    } else if (isPendente) {
      textoBadge = "PROCESSANDO";
      corBadge = Colors.amber;
    } else if (isSaida) {
      textoBadge = "SAQUE";
      corBadge = Colors.redAccent;
    }

    String dataFormatada = "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D), 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A1A1A)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFF1E1E1E), shape: BoxShape.circle),
            child: Icon(iconeLista, color: cor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(local, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    // 🟢 REMOVIDO O 'const' DAQUI DEBAIXO:
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A), 
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      textoBadge, 
                      style: TextStyle(color: corBadge, fontSize: 9, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(dataFormatada, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
                ],
              ),
              ],
            ),
          ),
          Text("$sinalOperacao ${valor.toStringAsFixed(2)}", style: TextStyle(color: cor, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildItemMulta(String desc, DateTime data, double valor) {
    String dataFormatada = "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF331111)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFF2A1111), shape: BoxShape.circle),
            child: const Icon(Icons.remove, color: Colors.redAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      // 🟢 REMOVIDO O 'const' DAQUI TAMBÉM:
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1111), 
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "MULTA", 
                        style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(dataFormatada, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Text("- R\$ ${valor.toStringAsFixed(2)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}