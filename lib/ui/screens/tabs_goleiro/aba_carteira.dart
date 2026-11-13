import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:defendepramim/core/dinheiro.dart';

class AbaCarteira extends StatefulWidget {
  const AbaCarteira({super.key});

  @override
  State<AbaCarteira> createState() => _AbaCarteiraState();
}

class _AbaCarteiraState extends State<AbaCarteira> {
  final Color primaryColor = const Color(0xFF00E676);
  final Color backgroundColor = Colors.black;

  String _filtroAtual = 'Tudo';

  void _showSnackBar(String texto, {Color cor = Colors.blue}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SAQUE — só pede ao servidor (Callable solicitarSaque)
  // ---------------------------------------------------------------------------
  Future<void> _iniciarFluxoSaque(
    BuildContext context,
    String uid,
    double saldoDisponivel,
    Color primary,
  ) async {
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

      if (chavePix == null || chavePix.toString().trim().isEmpty) {
        _showSnackBar("Cadastre sua chave PIX na aba 'Perfil' para poder sacar!", cor: Colors.orange);
        return;
      }

      _abrirModalDigitacaoSaque(
        context,
        uid,
        chavePix.toString(),
        tipoPix?.toString() ?? '',
        saldoDisponivel,
        primary,
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      _showSnackBar("Erro ao verificar dados da conta: $e", cor: Colors.red);
    }
  }

  void _abrirModalDigitacaoSaque(
    BuildContext context,
    String uid,
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
          final bottomPadding = MediaQuery.of(ctx).padding.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 24 + bottomPadding),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Livre para saque: R\$ ${saldoMaximo.toStringAsFixed(2)}\nPIX: $chavePix",
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: valorController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixText: "R\$ ",
                      prefixStyle: const TextStyle(color: Colors.white54, fontSize: 24),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: TextButton(
                        onPressed: () => setStateSB(
                          () => valorController.text = saldoMaximo.toStringAsFixed(2),
                        ),
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
                              final textoValor = valorController.text.replaceAll(',', '.');
                              final valorSaque = double.tryParse(textoValor);

                              if (valorSaque == null || valorSaque <= 0) {
                                _showSnackBar("Digite um valor válido!", cor: Colors.orange);
                                return;
                              }
                              if (valorSaque > saldoMaximo) {
                                _showSnackBar("Saldo insuficiente para este valor.", cor: Colors.red);
                                return;
                              }

                              setStateSB(() => processando = true);

                              try {
                                final valorCentavos = Dinheiro.paraCentavos(valorSaque);
                                final idempotencyKey = const Uuid().v4();

                                final callable = FirebaseFunctions.instanceFor(
                                  region: 'southamerica-east1',
                                ).httpsCallable('solicitarSaque');

                                await callable.call({
                                  'valorCentavos': valorCentavos,
                                  'idempotencyKey': idempotencyKey,
                                });

                                if (context.mounted) {
                                  FocusScope.of(context).unfocus();
                                  Navigator.pop(ctx);
                                  _showSnackBar("Saque solicitado com sucesso!", cor: Colors.green);
                                }
                              } on FirebaseFunctionsException catch (e) {
                                setStateSB(() => processando = false);
                                _showSnackBar(e.message ?? "Erro ao solicitar saque.", cor: Colors.red);
                              } catch (e) {
                                setStateSB(() => processando = false);
                                _showSnackBar("Erro: $e", cor: Colors.red);
                              }
                            },
                      child: processando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : const Text(
                              "CONFIRMAR SAQUE",
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
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

  // ---------------------------------------------------------------------------
  // DETALHES DO LANÇAMENTO (ledger)
  // ---------------------------------------------------------------------------
  void _mostrarDetalhesTransacao(
    Map<String, dynamic> data,
    Color color,
    String prefix,
    String tipoTexto,
    String descricaoCustomizada,
  ) {
    final int centavos = _centavosDe(data);
    final double valor = Dinheiro.paraReal(centavos);

    final DateTime dt = (data['criadoEm'] as Timestamp?)?.toDate() ??
        (data['data'] as Timestamp?)?.toDate() ??
        DateTime.now();

    final dataTransacaoFormatada =
        "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;

        return Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 24 + bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
                child: Icon(
                  color == primaryColor ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: color,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tipoTexto,
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                "$prefix R\$ ${valor.toStringAsFixed(2)}",
                style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
              _linhaRecibo("Descrição", descricaoCustomizada),
              _linhaRecibo("Data do Lançamento", dataTransacaoFormatada),
              _linhaRecibo("Tipo", (data['tipo'] ?? 'geral').toString().toUpperCase()),
              if (data['idempotencyKey'] != null)
                _linhaRecibo("ID", data['idempotencyKey'].toString()),
              if (data['idJogo'] != null) _linhaRecibo("Jogo", data['idJogo'].toString()),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("FECHAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _linhaRecibo(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lê centavos do ledger (oficial) ou valor legado em R$.
  int _centavosDe(Map<String, dynamic> data) {
    if (data['valorCentavos'] is int) return data['valorCentavos'] as int;
    if (data['valorCentavos'] is num) return (data['valorCentavos'] as num).round();
    if (data['valor'] is num) return Dinheiro.paraCentavos((data['valor'] as num).toDouble());
    return 0;
  }

  bool _isEntrada(String tipo) {
    return tipo == 'recebimento_jogo' ||
        tipo == 'recarga' ||
        tipo == 'saque_recusado' ||
        tipo == 'estorno_contestacao' ||
        tipo == 'recebimento';
  }

  bool _isSaida(String tipo) {
    return tipo == 'saque_solicitado' ||
        tipo == 'saque_pago' ||
        tipo == 'pagamento_jogo' ||
        tipo == 'multa_desistencia' ||
        tipo == 'abatimento_multa' ||
        tipo == 'saida';
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text("Usuário não logado", style: TextStyle(color: Colors.white)));
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          // SALDO OFICIAL
          stream: FirebaseFirestore.instance.collection('carteiras').doc(uid).snapshots(),
          builder: (context, carteiraSnapshot) {
            if (carteiraSnapshot.hasError) {
              return const Center(
                child: Text("Erro ao carregar carteira", style: TextStyle(color: Colors.white)),
              );
            }
            if (carteiraSnapshot.connectionState == ConnectionState.waiting && !carteiraSnapshot.hasData) {
              return Center(child: CircularProgressIndicator(color: primaryColor));
            }

            final carteira = (carteiraSnapshot.data?.data() as Map<String, dynamic>?) ?? {};
            final int saldoCentavos = (carteira['saldoCentavos'] as num?)?.round() ?? 0;
            final int multasCentavos = (carteira['multasPendentesCentavos'] as num?)?.round() ?? 0;
            final int retidoCentavos = (carteira['retidoCentavos'] as num?)?.round() ?? 0;

            final double saldoBruto = Dinheiro.paraReal(saldoCentavos);
            final double multasPendentes = Dinheiro.paraReal(multasCentavos);
            final double valorRetido = Dinheiro.paraReal(retidoCentavos);

            // Disponível = saldo - retido (multas são dívida separada; gari abate sozinho)
            double saldoLiquidoParaSaque = saldoBruto - valorRetido;
            if (saldoLiquidoParaSaque < 0) saldoLiquidoParaSaque = 0.0;

            return StreamBuilder<QuerySnapshot>(
              // HISTÓRICO OFICIAL (ledger)
              stream: FirebaseFirestore.instance
                  .collection('ledger')
                  .where('uid', isEqualTo: uid)
                  .snapshots(),
              builder: (context, ledgerSnapshot) {
                if (ledgerSnapshot.hasError) {
                  return const Center(
                    child: Text("Erro ao carregar extrato", style: TextStyle(color: Colors.white)),
                  );
                }

                var docs = ledgerSnapshot.data?.docs ?? [];

                // Ordenar no cliente (evita índice composto obrigatório no arranque)
                docs = List.from(docs);
                docs.sort((a, b) {
                  final da = (a.data() as Map)['criadoEm'] as Timestamp?;
                  final db_ = (b.data() as Map)['criadoEm'] as Timestamp?;
                  if (da == null && db_ == null) return 0;
                  if (da == null) return 1;
                  if (db_ == null) return -1;
                  return db_.compareTo(da);
                });

                if (_filtroAtual != 'Tudo') {
                  docs = docs.where((doc) {
                    final item = doc.data() as Map<String, dynamic>;
                    final tipo = (item['tipo'] ?? '').toString();
                    if (_filtroAtual == 'Entradas') return _isEntrada(tipo);
                    if (_filtroAtual == 'Saques') {
                      return tipo == 'saque_solicitado' ||
                          tipo == 'saque_pago' ||
                          tipo == 'saque_recusado';
                    }
                    return true;
                  }).toList();
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  children: [
                    const Text(
                      "Sua Carteira",
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _cardSaldoGoleiro(
                      context,
                      uid,
                      saldoLiquidoParaSaque,
                      saldoBruto,
                      multasPendentes,
                      primaryColor,
                    ),
                    const SizedBox(height: 16),
                    if (valorRetido > 0 || multasPendentes > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            if (valorRetido > 0)
                              Expanded(
                                child: _cardStatusEspecial(
                                  "VALOR RETIDO",
                                  valorRetido,
                                  Icons.lock_clock,
                                  Colors.orangeAccent,
                                ),
                              ),
                            if (valorRetido > 0 && multasPendentes > 0) const SizedBox(width: 10),
                            if (multasPendentes > 0)
                              Expanded(
                                child: _cardStatusEspecial(
                                  "MULTAS PENDENTES",
                                  multasPendentes,
                                  Icons.gavel_rounded,
                                  Colors.redAccent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    const Text(
                      "Movimentações",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildFiltros(),
                    const SizedBox(height: 16),
                    if (docs.isEmpty) _buildEmptyState(),
                    ...docs.map((doc) {
                      final item = Map<String, dynamic>.from(doc.data() as Map);
                      item['id'] = doc.id;
                      return _buildItemHistoricoGoleiro(item, primaryColor);
                    }),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS
  // ---------------------------------------------------------------------------
  Widget _buildFiltros() {
    return Row(
      children: [
        _chipFiltro('Tudo'),
        const SizedBox(width: 8),
        _chipFiltro('Entradas'),
        const SizedBox(width: 8),
        _chipFiltro('Saques'),
      ],
    );
  }

  Widget _chipFiltro(String titulo) {
    final bool ativo = _filtroAtual == titulo;
    return GestureDetector(
      onTap: () => setState(() => _filtroAtual = titulo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? primaryColor : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? primaryColor : Colors.white12),
        ),
        child: Text(
          titulo,
          style: TextStyle(
            color: ativo ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _cardSaldoGoleiro(
    BuildContext context,
    String uid,
    double saldoLiquido,
    double saldoBruto,
    double multas,
    Color primary,
  ) {
    final bool temSaldoParaSaque = saldoLiquido > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0D1F14),
        border: Border.all(color: const Color(0xFF1A3324)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DISPONÍVEL PARA SAQUE",
                style: TextStyle(
                  color: primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(Icons.account_balance_wallet_outlined, color: primary, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "R\$ ${saldoLiquido.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          if (multas > 0) ...[
            const SizedBox(height: 4),
            Text(
              "Saldo em conta: R\$ ${saldoBruto.toStringAsFixed(2)} | Multas: R\$ ${multas.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: temSaldoParaSaque
                  ? () => _iniciarFluxoSaque(context, uid, saldoLiquido, primary)
                  : null,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: temSaldoParaSaque ? Colors.black : const Color(0xFF555555),
              ),
              label: Text(
                "SOLICITAR SAQUE",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: temSaldoParaSaque ? Colors.black : const Color(0xFF555555),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                disabledBackgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardStatusEspecial(String titulo, double valor, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: cor.withAlpha(50)),
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
          Text(
            "R\$ ${valor.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildItemHistoricoGoleiro(Map<String, dynamic> item, Color primaryColor) {
    final String tipo = (item['tipo'] ?? '').toString();
    final int centavos = _centavosDe(item);
    final double valor = Dinheiro.paraReal(centavos);
    final String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');

    String local = (item['descricao'] ?? 'Transação').toString();
    final DateTime data = (item['criadoEm'] as Timestamp?)?.toDate() ??
        (item['data'] as Timestamp?)?.toDate() ??
        DateTime.now();

    bool isSaida = _isSaida(tipo);
    String prefix = isSaida ? "-" : "+";
    Color color = isSaida ? Colors.redAccent : primaryColor;
    IconData icon = isSaida ? Icons.account_balance_wallet_outlined : Icons.sports_soccer_outlined;
    String textoBadge = isSaida ? "SAÍDA" : "ENTRADA";

    switch (tipo) {
      case 'recebimento_jogo':
      case 'recebimento':
        textoBadge = "RECEBIMENTO";
        color = primaryColor;
        icon = Icons.sports_soccer_outlined;
        prefix = "+";
        break;
      case 'saque_solicitado':
        textoBadge = "SAQUE";
        color = Colors.amber;
        icon = Icons.access_time_rounded;
        prefix = "-";
        break;
      case 'saque_pago':
        textoBadge = "SAQUE PAGO";
        color = primaryColor;
        icon = Icons.check_circle_outline;
        prefix = "-";
        local = "Saque efetuado na conta";
        break;
      case 'saque_recusado':
        textoBadge = "ESTORNO SAQUE";
        color = Colors.orangeAccent;
        icon = Icons.undo_rounded;
        prefix = "+";
        local = "Saque recusado (estornado)";
        break;
      case 'multa_desistencia':
      case 'abatimento_multa':
        textoBadge = "MULTA";
        color = Colors.orangeAccent;
        icon = Icons.warning_amber_rounded;
        prefix = "-";
        break;
      case 'estorno_contestacao':
        textoBadge = "ESTORNO";
        color = primaryColor;
        icon = Icons.undo_rounded;
        prefix = "+";
        break;
      case 'recarga':
        textoBadge = "RECARGA";
        color = primaryColor;
        icon = Icons.add_circle_outline;
        prefix = "+";
        break;
      case 'pagamento_jogo':
        textoBadge = "PAGAMENTO";
        color = Colors.redAccent;
        icon = Icons.payment;
        prefix = "-";
        break;
    }

    final dataFormatada =
        "${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _mostrarDetalhesTransacao(item, color, prefix, textoBadge, local),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textoBadge,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      local,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(dataFormatada, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "$prefix R\$ $valorFormatado",
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
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
            _filtroAtual == 'Tudo' ? "NENHUMA MOVIMENTAÇÃO" : "NENHUM REGISTRO",
            style: TextStyle(
              color: Colors.white.withAlpha(51),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filtroAtual == 'Tudo'
                ? "Suas entradas e saídas aparecerão aqui."
                : "Não há dados para o filtro selecionado.",
            style: TextStyle(
              color: Colors.white.withAlpha(26),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
