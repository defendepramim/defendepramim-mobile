import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:defendepramim/ui/screens/convocacao/tela_criar_jogo.dart';

class CardJogoContratante extends StatefulWidget {
  final Map<String, dynamic> jogo;
  final Color cor;

  const CardJogoContratante({super.key, required this.jogo, required this.cor});

  @override
  State<CardJogoContratante> createState() => _CardJogoContratanteState();
}

class _CardJogoContratanteState extends State<CardJogoContratante> {
  bool _isLoading = false;
  Timer? _timer;
  
  // --- ADICIONE ESTA VARIÁVEL ---
  Duration _diferencaServidor = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sincronizarRelogio(); // Chama a sincronização ao iniciar
    
    // Timer de 30 segundos (igual ao seu outro código) para atualizar a tela
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  // --- ADICIONE ESTE MÉTODO (O "Coração" da sincronização) ---
  Future<void> _sincronizarRelogio() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('temp_time').doc('server_time');
      await docRef.set({'time': FieldValue.serverTimestamp()});
      final snap = await docRef.get();
      final Timestamp? serverTimestamp = snap.data()?['time'];

      if (serverTimestamp != null && mounted) {
        setState(() {
          _diferencaServidor = serverTimestamp.toDate().difference(DateTime.now());
        });
      }
    } catch (e) {
      debugPrint("Erro ao sincronizar relógio: $e");
    }
  }

  // Helper para facilitar o uso no código
  DateTime _obterHoraRealAgora() => DateTime.now().add(_diferencaServidor);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showSnackBar(String texto, {Color cor = Colors.blue}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: cor, behavior: SnackBarBehavior.floating),
    );
  }

  

  // --- 🛡️ LÓGICA DE CONTESTAÇÃO (NOVA) ---
  Future<void> _abrirModalContestacao() async {
    final motivos = [
      "Goleiro não apareceu (W.O.)",
      "Goleiro chegou muito atrasado",
      "Comportamento inadequado",
      "Nível técnico abaixo do esperado",
      "Outro"
    ];

    String? motivoSelecionado;
    final TextEditingController outroController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Contestar Partida", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Por que você está contestando este jogo?", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                ...motivos.map((m) => RadioListTile<String>(
                  title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  value: m,
                  groupValue: motivoSelecionado,
                  activeColor: const Color(0xFF00E676),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                )),
                if (motivoSelecionado == "Outro") ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: outroController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: "Descreva o ocorrido...",
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                ]
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: (motivoSelecionado == null) ? null : () {
                String justificativa = motivoSelecionado == "Outro" ? outroController.text : motivoSelecionado!;
                Navigator.pop(ctx);
                _executarContestacao(justificativa);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text("ENVIAR CONTESTAÇÃO"),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _executarContestacao(String justificativa) async {
    // Validação básica de tamanho
    if (justificativa.trim().length < 10) {
      _showSnackBar("Por favor, descreva o motivo com pelo menos 10 caracteres.", cor: Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection("jogos").doc(widget.jogo['id']).update({
        "status": "contestado",
        "contestacao": {
          "autor": "contratante",
          "motivo": justificativa.trim(),
          "data": FieldValue.serverTimestamp(),
          "statusMediacao": "aguardando_goleiro",
        }
      });
      _showSnackBar("Contestação registrada. Nossa equipe analisará o caso.", cor: Colors.orange);
    } catch (e) {
      _showSnackBar("Erro ao processar contestação.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmarPagamentoDialog() async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Liberar Pagamento?", 
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: const Text(
        "Você confirma que o goleiro compareceu e a partida foi realizada conforme o combinado?",
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("SIM, LIBERAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirmar == true) {
    _pagarGoleiro();
  }
}

  // --- 💸 LÓGICA DE PAGAMENTO ---
  Future<void> _pagarGoleiro() async {
    final idGoleiro = widget.jogo['idGoleiro'];
    final idJogo = widget.jogo['id'];
    // Força o cast para double para evitar erro de tipo no Firebase
    final double valorGoleiro = (widget.jogo['valor'] ?? 0.0).toDouble();

    if (idGoleiro == null || idJogo == null) {
       _showSnackBar("Dados do jogo incompletos para pagamento.", cor: Colors.red);
       return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference jogoRef = FirebaseFirestore.instance.collection("jogos").doc(idJogo);
        DocumentReference goleiroRef = FirebaseFirestore.instance.collection("usuarios").doc(idGoleiro);

        // 1. Atualiza o status do jogo
        transaction.update(jogoRef, {
          "status": "finalizado", 
          "pagoEm": FieldValue.serverTimestamp()
        });

        // 2. Incrementa o saldo do goleiro
        transaction.update(goleiroRef, {
          "saldo": FieldValue.increment(valorGoleiro)
        });
        
        // 3. Cria o registro no extrato do goleiro
        DocumentReference extratoGoleiro = goleiroRef.collection('extrato').doc();
        transaction.set(extratoGoleiro, {
          "id": extratoGoleiro.id,
          "tipo": "recebimento",
          "valor": valorGoleiro,
          "data": FieldValue.serverTimestamp(),
          "descricao": "Pelada: ${widget.jogo['local']}",
          "idJogo": idJogo,
          "status": "concluido"
        });
      });
      _showSnackBar("Pagamento liberado! O goleiro já recebeu.", cor: Colors.green);
    } catch (e) {
      _showSnackBar("Erro ao processar transação financeira.", cor: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ❌ LÓGICA DE CANCELAMENTO ---
Future<void> _cancelarPartida() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  // 1. Cálculos de Multa e Estorno
  final DateTime dataDoJogo = (widget.jogo['dataHora'] as Timestamp).toDate();
  final int dHoras = dataDoJogo.difference(DateTime.now()).inHours;
  final double valorTotal = (widget.jogo['valor'] ?? 0.0).toDouble();

  // Regra: Menos de 4 horas para o jogo = multa de 10 reais
  double multa = (dHoras < 4) ? 10.0 : 0.0;
  double valorEstorno = (valorTotal - multa).clamp(0, 9999);

  // 2. Abre o Modal para pegar o motivo
  final resultado = await _dialogConfirmarCancelamento(multa, valorEstorno);
  if (resultado == null || resultado['confirmado'] != true) return;

  final String motivoFinal = resultado['motivo'];

  setState(() => _isLoading = true);

  try {
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentReference jogoRef = FirebaseFirestore.instance.collection("jogos").doc(widget.jogo['id']);
      DocumentReference userRef = FirebaseFirestore.instance.collection("usuarios").doc(uid);

      // 3. Atualiza o Jogo (Dados para o Goleiro ler)
      transaction.update(jogoRef, {
        "status": "cancelado",
        "canceladoEm": FieldValue.serverTimestamp(),
        "canceladoPor": "contratante",
        "motivoCancelamento": motivoFinal,
        "multaRetida": multa,
        "valorEstornado": valorEstorno,
      });

      // 4. Estorno do Saldo para o Contratante
      transaction.update(userRef, {"saldo": FieldValue.increment(valorEstorno)});

      // 5. Registro de Extrato: Estorno
      DocumentReference extratoEstorno = userRef.collection('extrato').doc();
      transaction.set(extratoEstorno, {
        "id": extratoEstorno.id,
        "tipo": "estorno",
        "valor": valorEstorno,
        "data": FieldValue.serverTimestamp(),
        "descricao": "Estorno: ${widget.jogo['local']}",
        "idJogo": widget.jogo['id'],
      });

      // 6. Registro de Extrato: Multa (se houver)
      if (multa > 0) {
        DocumentReference extratoMulta = userRef.collection('extrato').doc();
        transaction.set(extratoMulta, {
          "id": extratoMulta.id,
          "tipo": "multa_cancelamento",
          "valor": multa,
          "data": FieldValue.serverTimestamp(),
          "descricao": "Taxa de cancelamento (< 4h)",
          "idJogo": widget.jogo['id'],
        });
      }
    });

    _showSnackBar("Partida cancelada e saldo estornado.", cor: Colors.green);
  } catch (e) {
    _showSnackBar("Erro ao processar cancelamento. Tente novamente.", cor: Colors.red);
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

Future<Map<String, dynamic>?> _dialogConfirmarCancelamento(double multa, double estorno) {
  String? motivoSelecionado;
  final TextEditingController outroController = TextEditingController();
  final motivos = ["Campo cancelou", "Time desistiu", "Problema pessoal", "Consegui outro goleiro", "Outro"];

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setStateSB) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirmar Cancelamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                multa > 0 
                  ? "Atenção: Multa de R\$ ${multa.toStringAsFixed(2)} aplicada por cancelamento em cima da hora.\nEstorno: R\$ ${estorno.toStringAsFixed(2)}"
                  : "Deseja cancelar? Estorno integral de R\$ ${estorno.toStringAsFixed(2)} será realizado.",
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Motivo do cancelamento:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              ...motivos.map((m) => RadioListTile<String>(
                title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
                value: m,
                groupValue: motivoSelecionado,
                onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                activeColor: const Color(0xFF00E676),
                contentPadding: EdgeInsets.zero,
              )),
              if (motivoSelecionado == "Outro") ...[
                const SizedBox(height: 10),
                TextField(
                  controller: outroController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Explique o motivo...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("VOLTAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: (motivoSelecionado == null || (motivoSelecionado == "Outro" && outroController.text.isEmpty)) 
              ? null 
              : () => Navigator.pop(ctx, {
                  "confirmado": true,
                  "motivo": motivoSelecionado == "Outro" ? outroController.text : motivoSelecionado
                }), 
            child: const Text("CONFIRMAR CANCELAMENTO"),
          ),
        ],
      ),
    ),
  );
}

void _mostrarOpcoes() {
    final dt = (widget.jogo['dataHora'] as Timestamp).toDate();
    final agora = _obterHoraRealAgora(); // MUDANÇA AQUI
    final status = widget.jogo['status'];

    // Se o jogo já finalizou, foi cancelado ou está em disputa, não abre menu de edição
    if (['finalizado', 'cancelado', 'contestado'].contains(status)) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 15),
          
          if (agora.isBefore(dt))
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Editar Detalhes", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => TelaCriarJogo(dados: widget.jogo), 
                  fullscreenDialog: true
                ));
              },
            ),
          ListTile(
            leading: const Icon(Icons.cancel, color: Colors.redAccent),
            title: const Text("Cancelar Partida", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _cancelarPartida();
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

@override
Widget build(BuildContext context) {
  final status = widget.jogo['status'] ?? 'aberto';
  final dt = (widget.jogo['dataHora'] as Timestamp).toDate();
  final duracao = widget.jogo['duracao'] ?? 60;
  
  // 1. Cálculos de Tempo
  final fimPartida = dt.add(Duration(minutes: duracao));
  final agora = _obterHoraRealAgora();
  final bool jaTerminou = agora.isAfter(fimPartida);
  
  // O limite é 12h após o FIM
  final limitePagamento = fimPartida.add(const Duration(hours: 12));
  final restante = limitePagamento.difference(agora);
  final bool expirouPrazo = restante.isNegative;

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A), 
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.05))
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: (status == 'aberto' || status == 'fechado') ? _mostrarOpcoes : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.jogo['local']?.toUpperCase() ?? 'ARENA', 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.access_time, color: Colors.grey, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              "${dt.day}/${dt.month} às ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}",
                              style: const TextStyle(color: Colors.grey, fontSize: 13)
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "R\$ ${widget.jogo['valor']}", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(status),
                    ],
                  ),
                ],
              ),
            ),

            // --- 🚨 BANNER DE ALERTA (12 HORAS) ---
            if (jaTerminou && status == 'fechado' && !expirouPrazo)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: Colors.orangeAccent.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Ação necessária: O pagamento será liberado automaticamente em ${restante.inHours}h ${restante.inMinutes % 60}m.",
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Botoões ou status de processamento
            if (jaTerminou && status == 'fechado') _buildBotoesAcao(expirouPrazo),
            
            if (_isLoading) 
              const LinearProgressIndicator(minHeight: 2, color: Color(0xFF00E676), backgroundColor: Colors.transparent),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildStatusBadge(String status) {
    String label = status.toUpperCase();
    Color color = Colors.grey;

    if (status == 'contestado') {
      final contestacao = widget.jogo['contestacao'];
      final sub = contestacao is Map ? contestacao['statusMediacao'] : null;
      label = sub == 'aguardando_goleiro' ? "EM DISPUTA (ANÁLISE)" : "EM MEDIAÇÃO";
      color = Colors.redAccent;
    } else {
      switch (status) {
        case 'aberto': color = Colors.orangeAccent; label = "BUSCANDO GOLEIRO"; break;
        case 'fechado': color = const Color(0xFF00E676); label = "CONFIRMADO"; break;
        case 'finalizado': color = Colors.blueAccent; label = "PAGO"; break;
        case 'cancelado': color = Colors.white24; label = "CANCELADO"; break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildBotoesAcao(bool expirou) {
  // Se o prazo de 12h venceu, não deixa mais contestar nem clicar
  if (expirou) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      alignment: Alignment.center,
      child: const Text(
        "AGUARDANDO PROCESSAMENTO DO PAGAMENTO",
        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _abrirModalContestacao,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("CONTESTAR", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _confirmarPagamentoDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("LIBERAR PAGAMENTO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ),
        ),
      ],
    ),
  );
}
} // <--- ESSA É A ÚLTIMA CHAVE QUE FECHA A CLASSE STATE