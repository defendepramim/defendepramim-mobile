import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'package:uuid/uuid.dart'; 

class AbaFinanceiroContratante extends StatefulWidget {
  const AbaFinanceiroContratante({super.key});

  @override
  State createState() => _AbaFinanceiroContratanteState();
}

class _AbaFinanceiroContratanteState extends State {
  final Color primaryColor = const Color(0xFF00E676);
  bool _isProcessing = false;

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

  Future _iniciarFluxoSaque(BuildContext context, String uid, double saldoDisponivel, Color primary, Map userDados) async {
    _showSnackBar("Sistema de saques em manutenção para migração bancária (V2).", cor: Colors.orange);
  }

  Future _adicionarSaldoTeste(BuildContext context) async {
    // Recarga liberada para testes externos (Callable de teste; gateway PIX real entra depois)
    final TextEditingController valorRecargaController = TextEditingController();
    final uid = FirebaseAuth.instance.currentUser?.uid;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctxDialog) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text("Recarga de Teste", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: TextField(
              controller: valorRecargaController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: "R\$ ",
                prefixStyle: const TextStyle(color: Colors.white54, fontSize: 24),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            actions: [
              if (!_isProcessing)
                TextButton(
                  onPressed: () => Navigator.pop(ctxDialog), 
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing ? null : () async {
                  double valor = double.tryParse(valorRecargaController.text.replaceAll(',', '.')) ?? 0;
                  if (valor <= 0) return;
                  if (uid == null) return;

                  setStateDialog(() => _isProcessing = true);
                  FocusScope.of(context).unfocus(); 

                  try {
                    int valorCentavos = (valor * 100).round();
                    String idempotencyKey = const Uuid().v4();

                    // 🚀 CORREÇÃO 1: Definir a região sul-americana para evitar o erro NOT_FOUND
                    final callable = FirebaseFunctions.instanceFor(region: 'southamerica-east1').httpsCallable('iniciarRecarga');
                    
                    await callable.call({
                      'valorCentavos': valorCentavos,
                      'idempotencyKey': idempotencyKey,
                    });

                    if (mounted) {
                      Navigator.pop(ctxDialog);
                      _showSnackBar("Recarga de R\$ ${valor.toStringAsFixed(2)} processada pelo servidor!", cor: Colors.green);
                    }
                  } catch (e) {
                    if (mounted) _showSnackBar("Erro ao recarregar: $e", cor: Colors.red);
                  } finally {
                    setStateDialog(() => _isProcessing = false);
                  }
                },
                child: _isProcessing 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("CONFIRMAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return const Center(child: Text("Usuário não logado"));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder(
          stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
          builder: (context, userSnapshot) {
            Map dadosUser = {};
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              dadosUser = userSnapshot.data!.data() as Map;
            }

            return StreamBuilder(
              stream: FirebaseFirestore.instance.collection('carteiras').doc(uid).snapshots(),
              builder: (context, carteiraSnapshot) {
                double saldoReal = 0.0;
                if (carteiraSnapshot.hasData && carteiraSnapshot.data!.exists) {
                  int saldoCentavos = (carteiraSnapshot.data!.data() as Map)['saldoCentavos'] ?? 0;
                  saldoReal = saldoCentavos / 100.0;
                }

                return StreamBuilder(
                  stream: FirebaseFirestore.instance.collection('ledger').where('uid', isEqualTo: uid).snapshots(),
                  builder: (context, ledgerSnapshot) {
                    if (ledgerSnapshot.connectionState == ConnectionState.waiting && !ledgerSnapshot.hasData) {
                      return Center(child: CircularProgressIndicator(color: primaryColor));
                    }
                    
                    var docs = ledgerSnapshot.data?.docs ?? [];
                    var documentosAtuais = docs.map((d) => d.data() as Map).toList();

                    documentosAtuais.sort((a, b) {
                      Timestamp? ta = a['criadoEm'] as Timestamp?;
                      Timestamp? tb = b['criadoEm'] as Timestamp?;
                      if (ta == null && tb == null) return 0;
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta); 
                    });

                    if (_filtroAtual != 'Tudo') {
                      documentosAtuais = documentosAtuais.where((item) {
                        final tipo = item['tipo'] ?? '';
                        if (_filtroAtual == 'Entradas') {
                          return tipo == 'recarga';
                        } else if (_filtroAtual == 'Gastos') {
                          return tipo == 'pagamento_jogo' || tipo == 'pagamento_multa';
                        } else if (_filtroAtual == 'Saques') {
                          return tipo == 'saque';
                        }
                        return true;
                      }).toList();
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      children: [
                        const Text("Sua Carteira", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        _cardSaldoContratante(context, uid, saldoReal, primaryColor, dadosUser),
                        const SizedBox(height: 24), 
                        const Text("Movimentações", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildFiltros(),
                        const SizedBox(height: 16),
                        if (documentosAtuais.isEmpty) _buildEmptyState(),
                        ...documentosAtuais.map((data) => _buildItemExtrato(data, primaryColor)),
                      ],
                    );
                  },
                );
              }
            );
          },
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _chipFiltro('Tudo'), const SizedBox(width: 8),
          _chipFiltro('Entradas'), const SizedBox(width: 8),
          _chipFiltro('Gastos'), const SizedBox(width: 8),
          _chipFiltro('Saques'),
        ],
      ),
    );
  }

  Widget _chipFiltro(String titulo) {
    bool isSelected = _filtroAtual == titulo;
    return GestureDetector(
      onTap: () => setState(() => _filtroAtual = titulo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? primaryColor : Colors.white24),
        ),
        child: Text(titulo, style: TextStyle(color: isSelected ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _cardSaldoContratante(BuildContext context, String uid, double saldo, Color primary, Map userDados) {
    bool temSaldoParaSaque = saldo > 0;
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
              Text("SALDO TOTAL", style: TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0)), 
              Icon(Icons.account_balance_wallet_outlined, color: primary, size: 18), 
            ],
          ),
          const SizedBox(height: 4),
          Text("R\$ ${saldo.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: temSaldoParaSaque ? () => _iniciarFluxoSaque(context, uid, saldo, primary, userDados) : null,
                    icon: Icon(Icons.arrow_upward_rounded, size: 14, color: temSaldoParaSaque ? primary : Colors.white24),
                    label: Text("SACAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: temSaldoParaSaque ? primary : Colors.white24)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: temSaldoParaSaque ? primary.withAlpha(128) : Colors.white10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () => _adicionarSaldoTeste(context),
                    icon: const Icon(Icons.add_circle_outline, size: 14, color: Colors.black),
                    label: const Text("RECARREGAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: Colors.black)),
                    style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemExtrato(Map data, Color primary) {
    int valorCentavos = data['valorCentavos'] ?? 0;
    double valor = valorCentavos / 100.0;
    String tipo = data['tipo'] ?? '';
    String descricao = data['descricao'] ?? 'Transação';
    String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');
    
    final DateTime dt = (data['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    IconData icon; Color color; String prefix; String textoBadge;

    if (tipo == 'recarga') {
      icon = Icons.add_circle_outline;
      color = primary;
      prefix = "+";
      textoBadge = "RECARGA";
    } else if (tipo == 'estorno_cancelamento' ||
        tipo == 'estorno_expirado' ||
        tipo == 'estorno_contestacao' ||
        tipo == 'saque_recusado') {
      icon = Icons.undo_rounded;
      color = primary;
      prefix = "+";
      textoBadge = "ESTORNO";
    } else if (tipo == 'pagamento_multa' ||
        tipo == 'multa_desistencia' ||
        tipo == 'abatimento_multa') {
      icon = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
      prefix = "-";
      textoBadge = "MULTA";
    } else if (tipo == 'saque' || tipo == 'saque_solicitado' || tipo == 'saque_pago') {
      icon = Icons.account_balance_wallet_outlined;
      color = Colors.redAccent;
      prefix = "-";
      textoBadge = "SAQUE";
    } else if (tipo == 'pagamento_jogo') {
      icon = Icons.sports_soccer_outlined;
      color = Colors.redAccent;
      prefix = "-";
      textoBadge = "PAGAMENTO";
    } else {
      icon = Icons.receipt_long_outlined;
      color = Colors.white54;
      prefix = tipo.toString().contains('estorno') ? "+" : "-";
      textoBadge = tipo.toString().toUpperCase().replaceAll('_', ' ');
    }

    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    final String dataFormatada = "$dia/$mes às $hora:$minuto";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _mostrarDetalhesTransacao(data, color, prefix, textoBadge, descricao),
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
                      descricao,
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
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withAlpha(8), shape: BoxShape.circle), child: Icon(Icons.history_toggle_off_rounded, size: 60, color: Colors.white.withAlpha(26))),
          const SizedBox(height: 16),
          Text(_filtroAtual == 'Tudo' ? "NENHUMA MOVIMENTAÇÃO" : "NENHUM REGISTRO", style: TextStyle(color: Colors.white.withAlpha(51), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(_filtroAtual == 'Tudo' ? "Suas movimentações do novo banco aparecerão aqui." : "Não há dados para o filtro selecionado.", style: TextStyle(color: Colors.white.withAlpha(26), fontSize: 12)),
        ],
      ),
    );
  }

  void _mostrarDetalhesTransacao(Map data, Color color, String prefix, String tipoTexto, String descricaoCustomizada) {
    double valor = (data['valorCentavos'] ?? 0) / 100.0;
    String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');
    final DateTime dt = (data['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final ano = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    final String dataTransacaoFormatada = "$dia/$mes/$ano às $hora:$minuto";

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1E1E1E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 24 + bottomPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle), child: Icon(color == primaryColor ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: color, size: 32)),
              const SizedBox(height: 12),
              Text(tipoTexto, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text("$prefix R\$ $valorFormatado", style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),
              _linhaRecibo("Descrição / Local", descricaoCustomizada),
              _linhaRecibo("Data do Lançamento", dataTransacaoFormatada),
              if (data['idempotencyKey'] != null) _linhaRecibo("Chave da Transação", data['idempotencyKey'].toString().substring(0, 8) + "..."),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C2C2C), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.pop(ctx), child: const Text("FECHAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
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
          Expanded(child: Text(valor, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2))),
        ],
      ),
    );
  }
}