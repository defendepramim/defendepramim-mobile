import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AbaFinanceiroContratante extends StatefulWidget {
  const AbaFinanceiroContratante({super.key});

  @override
  State<AbaFinanceiroContratante> createState() => _AbaFinanceiroContratanteState();
}

class _AbaFinanceiroContratanteState extends State<AbaFinanceiroContratante> {
  final Color primaryColor = const Color(0xFF00E676);
  bool _isProcessing = false;

  // 🟢 Controle do filtro atual ('Tudo', 'Entradas', 'Gastos', 'Saques')
  String _filtroAtual = 'Tudo';

  // --- 🛰️ UTILITÁRIOS ---
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

  // --- 💸 LÓGICA DE SAQUE ENXUTA ---
  Future<void> _iniciarFluxoSaque(BuildContext context, String uid, double saldoDisponivel, Color primary, Map<String, dynamic> userDados) async {
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
      final nomeContratante = dados?['nome'] ?? "Contratante";

      // 🛑 TRAVA INTELIGENTE: Manda o cara pro Perfil se não tiver PIX!
      if (chavePix == null || chavePix.toString().trim().isEmpty) {
        _showSnackBar("Cadastre sua chave PIX na aba 'Perfil' para poder sacar!", cor: Colors.orange);
        return;
      }

      _abrirModalDigitacaoSaque(context, uid, nomeContratante, chavePix.toString(), tipoPix.toString(), saldoDisponivel, primary);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); 
      _showSnackBar("Erro ao verificar dados da conta: $e", cor: Colors.red);
    }
  }

  void _abrirModalDigitacaoSaque(BuildContext context, String uid, String nomeUsuario, String chavePix, String tipoPix, double saldoMaximo, Color primary) {
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
                      const Text("VALOR DO SAQUE", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx))
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text("Livre para saque: R\$ ${saldoMaximo.toStringAsFixed(2)}\nPIX: $chavePix", style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      suffixIcon: TextButton(
                        onPressed: () => setStateSB(() => valorController.text = saldoMaximo.toStringAsFixed(2)),
                        child: Text("TUDO", style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: processando
                          ? null
                          : () async {
                              String textoValor = valorController.text.replaceAll(',', '.');
                              double? valorSaque = double.tryParse(textoValor);

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
                                final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
                                final extratoRef = userRef.collection('extrato').doc();
                                final saqueRef = FirebaseFirestore.instance.collection('saques').doc();

                                await FirebaseFirestore.instance.runTransaction((transaction) async {
                                  DocumentSnapshot userSnap = await transaction.get(userRef);
                                  double saldoAtual = (userSnap.data() as Map<String, dynamic>?)?['saldo']?.toDouble() ?? 0.0;

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
                                    'nomeGoleiro': nomeUsuario, 
                                    'valor': valorSaque,
                                    'chavePix': chavePix,
                                    'tipoPix': tipoPix,
                                    'status': 'pendente',
                                    'idExtrato': extratoRef.id,
                                    'dataSolicitacao': FieldValue.serverTimestamp(),
                                  });
                                });

                                if (context.mounted) {
                                  FocusScope.of(context).unfocus(); 
                                  Navigator.pop(ctx);
                                  _showSnackBar("Saque solicitado com sucesso!", cor: Colors.green);
                                }
                              } catch (e) {
                                setStateSB(() => processando = false);
                                _showSnackBar("Erro: $e", cor: Colors.red);
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

  // --- 💰 RECARGA DE TESTE (BLINDADA) ---
  Future<void> _adicionarSaldoTeste(BuildContext context) async {
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
                  
                  if (valor <= 0) {
                    _showSnackBar("Digite um valor válido", cor: Colors.orange);
                    return;
                  }
                  if (uid == null) return;

                  setStateDialog(() => _isProcessing = true);
                  FocusScope.of(context).unfocus(); 

                  final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
                  final extratoRef = userRef.collection('extrato').doc();
                  
                  try {
                    await FirebaseFirestore.instance.runTransaction((transaction) async {
                      DocumentSnapshot userSnap = await transaction.get(userRef);
                      
                      double saldoAtual = double.tryParse((userSnap.data() as Map<String, dynamic>?)?['saldo']?.toString() ?? '0') ?? 0.0;
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
                        'categoria': 'recarga',
                        'status': 'concluido'
                      });
                    });

                    if (mounted) {
                      Navigator.pop(ctxDialog);
                      _showSnackBar("Recarga de R\$ ${valor.toStringAsFixed(2)} realizada!", cor: Colors.green);
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
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
          builder: (context, userSnapshot) {
            double saldoReal = 0.0;
            Map<String, dynamic> dadosUser = {};
            
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              dadosUser = userSnapshot.data!.data() as Map<String, dynamic>;
              saldoReal = double.tryParse(dadosUser['saldo']?.toString() ?? '0') ?? 0.0;
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .collection('extrato')
                  .orderBy('data', descending: true)
                  .snapshots(),
              builder: (context, extratoSnapshot) {
                if (extratoSnapshot.connectionState == ConnectionState.waiting && !extratoSnapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: primaryColor));
                }
                
                var documentosAtuais = extratoSnapshot.data?.docs ?? [];

                // 🟢 APLICANDO O FILTRO NA LISTA
                if (_filtroAtual != 'Tudo') {
                  documentosAtuais = documentosAtuais.where((doc) {
                    final item = doc.data() as Map<String, dynamic>;
                    final tipo = item['tipo'] ?? '';
                    final categoria = item['categoria'] ?? '';
                    
                    if (_filtroAtual == 'Entradas') {
                      return tipo == 'entrada' || tipo == 'estorno';
                    } else if (_filtroAtual == 'Gastos') {
                      return (tipo != 'entrada' && tipo != 'estorno' && categoria != 'saque') || tipo == 'multa_cancelamento';
                    } else if (_filtroAtual == 'Saques') {
                      return categoria == 'saque';
                    }
                    return true;
                  }).toList();
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  children: [
                    const Text(
                      "Sua Carteira", 
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 16),
                    
                    // Card super slim e focado no saldo
                    _cardSaldoContratante(context, uid, saldoReal, primaryColor, dadosUser),
                    
                    const SizedBox(height: 24), 
                    
                    const Text(
                      "Movimentações", 
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: 12),

                    _buildFiltros(),
                    const SizedBox(height: 16),
                    
                    if (documentosAtuais.isEmpty) _buildEmptyState(),

                    ...documentosAtuais.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return _buildItemExtrato(data, primaryColor);
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

  // --- WIDGETS VISUAIS ---

  Widget _buildFiltros() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _chipFiltro('Tudo'),
          const SizedBox(width: 8),
          _chipFiltro('Entradas'),
          const SizedBox(width: 8),
          _chipFiltro('Gastos'),
          const SizedBox(width: 8),
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
        child: Text(
          titulo,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _cardSaldoContratante(BuildContext context, String uid, double saldo, Color primary, Map<String, dynamic> userDados) {
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
              Text(
                "SALDO TOTAL", 
                style: TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0)
              ), 
              Icon(Icons.account_balance_wallet_outlined, color: primary, size: 18), 
            ],
          ),
          const SizedBox(height: 4),
          
          Text(
            "R\$ ${saldo.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: temSaldoParaSaque ? () => _iniciarFluxoSaque(context, uid, saldo, primary, userDados) : null,
                    icon: Icon(Icons.arrow_upward_rounded, size: 14, color: temSaldoParaSaque ? primary : Colors.white24),
                    label: Text(
                      "SACAR", 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: temSaldoParaSaque ? primary : Colors.white24)
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: temSaldoParaSaque ? primary.withAlpha(128) : Colors.white10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🟢 LAYOUT DE EXTRATO INTERATIVO (Clicável para ver detalhes)
  Widget _buildItemExtrato(Map<String, dynamic> data, Color primary) {
    final String tipo = data['tipo'] ?? 'saida';
    final double valor = double.tryParse(data['valor']?.toString() ?? '0') ?? 0.0;
    final String status = data['status'] ?? 'concluido';
    final String categoria = data['categoria'] ?? '';
    final String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');

    String local = data['descricao'] ?? 'Transação';
    
    // 🟢 CORREÇÃO DA HORA: Lê a hora do pagamento/recusa, se não tiver, lê a hora da solicitação
    final DateTime dt = (data['dataAtualizacao'] as Timestamp?)?.toDate() ?? (data['data'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    IconData icon;
    Color color;
    String prefix;
    String textoBadge;

    // 1. DEFINIÇÃO BASE DE CORES E TEXTOS
    if (tipo == 'entrada' || tipo == 'estorno') {
      icon = tipo == 'estorno' ? Icons.assignment_return_rounded : Icons.add_circle_outline; 
      color = primary; // Verde
      prefix = "+";
      textoBadge = tipo == 'estorno' ? "ESTORNO" : "CRÉDITO";
    } else if (tipo == 'multa_cancelamento') {
      icon = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
      prefix = "-";
      textoBadge = "MULTA";
    } else {
      // Saídas (Pagamentos de Jogos e Saques)
      icon = categoria == 'saque' ? Icons.account_balance_wallet_outlined : Icons.sports_soccer_outlined;
      color = Colors.redAccent;
      prefix = "-";
      textoBadge = categoria == 'saque' ? "SAQUE" : "PAGAMENTO";
    }

    // 2. STATUS DE SAQUE E PAGAMENTO (PENDENTE, RECUSADO, PAGO)
    if (categoria == 'saque') {
      if (status == 'pendente') {
        color = Colors.amber;
        icon = Icons.access_time_rounded;
        textoBadge = "PROCESSANDO";
      } else if (status == 'recusado') {
        color = Colors.redAccent;
        icon = Icons.cancel_outlined;
        textoBadge = "RECUSADO";
        local = "Saque recusado (Estornado)";
      } else if (status == 'pago') {
        color = primary; 
        icon = Icons.check_circle_outline;
        textoBadge = "EFETUADO";
        local = "Saque efetuado na conta";
      }
    } else {
       if (status == 'pendente') {
        color = Colors.amber;
        icon = Icons.access_time_rounded;
        textoBadge = "PROCESSANDO";
      } else if (status == 'recusado') {
        color = Colors.redAccent;
        icon = Icons.cancel_outlined;
        textoBadge = "RECUSADO";
      }
    }

    // Formatação de Data
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    String dataFormatada = "$dia/$mes às $hora:$minuto";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _mostrarDetalhesTransacao(data, color, prefix, textoBadge, local), // Passando o local
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
                      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
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

  // 🟢 Adicionamos o parâmetro descricaoCustomizada para ele herdar o texto customizado do extrato
  void _mostrarDetalhesTransacao(Map<String, dynamic> data, Color color, String prefix, String tipoTexto, String descricaoCustomizada) {
    final double valor = double.tryParse(data['valor']?.toString() ?? '0') ?? 0.0;
    final String valorFormatado = valor.toStringAsFixed(2).replaceAll('.', ',');
    
    // 🟢 HORA CORRIGIDA NO RECIBO TAMBÉM
    final DateTime dt = (data['dataAtualizacao'] as Timestamp?)?.toDate() ?? (data['data'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final ano = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    String dataTransacaoFormatada = "$dia/$mes/$ano às $hora:$minuto";

    // ⚽ Busca a data/hora exata do Jogo (se houver essa referência no documento)
    String? dataJogoFormatada;
    if (data['dataHoraJogo'] != null) {
      final DateTime dtJogo = (data['dataHoraJogo'] as Timestamp).toDate();
      final diaJ = dtJogo.day.toString().padLeft(2, '0');
      final mesJ = dtJogo.month.toString().padLeft(2, '0');
      final horaJ = dtJogo.hour.toString().padLeft(2, '0');
      final minutoJ = dtJogo.minute.toString().padLeft(2, '0');
      dataJogoFormatada = "$diaJ/$mesJ às $horaJ:$minutoJ";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;

        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: 24 + bottomPadding, 
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              
              // Ícone + Tipo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withAlpha(26), shape: BoxShape.circle),
                child: Icon(color == primaryColor ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(tipoTexto, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              
              // Valor em Destaque
              Text(
                "$prefix R\$ $valorFormatado", 
                style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900), // Corrigido fontSize para ficar grande como no do Goleiro
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),

              // Detalhes Completos
              _linhaRecibo("Descrição / Local", descricaoCustomizada),
              
              // ⚽ Se tiver a hora do jogo, destaca ela!
              if (dataJogoFormatada != null)
                _linhaRecibo("Horário da Partida", dataJogoFormatada),

              _linhaRecibo("Data do Lançamento", dataTransacaoFormatada),
              _linhaRecibo("Categoria", (data['categoria'] ?? 'geral').toString().toUpperCase()),
              if (data['id'] != null) _linhaRecibo("ID da Transação", data['id'].toString()),

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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}