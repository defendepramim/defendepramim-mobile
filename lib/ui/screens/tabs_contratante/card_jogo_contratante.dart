import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:defendepramim/ui/screens/convocacao/tela_criar_jogo.dart';
import 'package:defendepramim/services/push_notification_service.dart';

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
  Duration _diferencaServidor = Duration.zero;

@override
  void initState() {
    super.initState();
    PushNotificationService().inicializar();
    _sincronizarRelogio();
    
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

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

    Future<void> _mostrarModalAvaliacao(String idGoleiro) async {
    int estrelas = 5;
    bool enviando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Avalie o Goleiro", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Como foi o desempenho e o comportamento do goleiro na partida?", style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 0,
                children: List.generate(5, (index) {
                  return IconButton(
                    padding: const EdgeInsets.all(4), 
                    constraints: const BoxConstraints(), 
                    icon: Icon(
                      index < estrelas ? Icons.star_rounded : Icons.star_border_rounded,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () {
                      setStateSB(() => estrelas = index + 1);
                    },
                  );
                }),
              ),
              if (enviando) 
                const Padding(padding: EdgeInsets.only(top: 20), child: CircularProgressIndicator(color: Color(0xFF00E676))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx),
              child: const Text("PULAR", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
              onPressed: enviando ? null : () async {
                setStateSB(() => enviando = true);
                try {
                  final batch = FirebaseFirestore.instance.batch();

                  final goleiroRef = FirebaseFirestore.instance.collection('usuarios').doc(idGoleiro);
                  batch.update(goleiroRef, {
                    'somaAvaliacoes': FieldValue.increment(estrelas),
                    'totalAvaliacoes': FieldValue.increment(1),
                  });

                  final jogoRef = FirebaseFirestore.instance.collection('jogos').doc(widget.jogo['id']);
                  batch.update(jogoRef, {
                    'avaliacaoGoleiro': estrelas,
                  });

                  await batch.commit();

                  if (mounted) {
                    setState(() {
                      widget.jogo['avaliacaoGoleiro'] = estrelas;
                    });
                  }

                  if (context.mounted) Navigator.pop(ctx);
                  _showSnackBar("Avaliação enviada! Obrigado.", cor: Colors.green);
                } catch (e) {
                  setStateSB(() => enviando = false);
                  _showSnackBar("Erro ao salvar avaliação.", cor: Colors.red);
                }
              },
              child: const Text("AVALIAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirModalContestacao() async {
    final motivos = ["Goleiro não apareceu (W.O.)", "Goleiro chegou muito atrasado", "Comportamento inadequado", "Nível técnico abaixo do esperado", "Outro"];
    String? motivoSelecionado;
    final TextEditingController detalheController = TextEditingController();

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
                const Text("Selecione o motivo principal e detalhe abaixo:", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                ...motivos.map((m) => RadioListTile<String>(
                  title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  value: m,
                  groupValue: motivoSelecionado,
                  activeColor: const Color(0xFF00E676),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                )),
                const SizedBox(height: 10),
                const Divider(color: Colors.white10),
                const SizedBox(height: 10),
                TextField(
                  controller: detalheController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Descreva detalhes do ocorrido...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: (motivoSelecionado == null) ? null : () {
                String textoFinal = "[$motivoSelecionado] ${detalheController.text}";
                Navigator.pop(ctx);
                _executarContestacao(textoFinal);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                disabledBackgroundColor: Colors.white10
              ),
              child: const Text("ENVIAR CONTESTAÇÃO"),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _executarContestacao(String justificativa) async {
    if (justificativa.trim().length < 10) {
      _showSnackBar("Por favor, descreva o motivo com pelo menos 10 caracteres.", cor: Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final jogoRef = FirebaseFirestore.instance.collection("jogos").doc(widget.jogo['id']);
      final contratanteRef = FirebaseFirestore.instance.collection("usuarios").doc(widget.jogo['idContratante']);

      batch.update(jogoRef, {
        "status": "contestado",
        "contestacao": {
          "autor": "contratante",
          "motivo": justificativa.trim(),
          "data": FieldValue.serverTimestamp(),
          "statusMediacao": "aguardando_goleiro",
        }
      });

      batch.update(contratanteRef, {
        "jogosContestados": FieldValue.increment(1) 
      });

      await batch.commit();
      _showSnackBar("Contestação registrada. Nossa equipe analisará o caso.", cor: Colors.orange);
      
      if (widget.jogo['idGoleiro'] != null) {
        await _mostrarModalAvaliacao(widget.jogo['idGoleiro']);
      }
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
        title: const Text("Liberar Pagamento?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Future<void> _pagarGoleiro() async {
    final idGoleiro = widget.jogo['idGoleiro'];
    final idJogo = widget.jogo['id'];
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
        DocumentReference contratanteRef = FirebaseFirestore.instance.collection("usuarios").doc(widget.jogo['idContratante']);

        transaction.update(jogoRef, {
          "status": "finalizado", 
          "pagoEm": FieldValue.serverTimestamp(),
        });

        transaction.update(goleiroRef, {
          "saldo": FieldValue.increment(valorGoleiro),
          "atuadas": FieldValue.increment(1) 
        });
        
        transaction.update(contratanteRef, {
          "jogosRealizados": FieldValue.increment(1)
        });
        
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
      await _mostrarModalAvaliacao(idGoleiro);

    } catch (e) {
      _showSnackBar("Erro ao processar transação financeira.", cor: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🟢 AQUI ESTÁ A CORREÇÃO DO EXTRATO NO CANCELAMENTO
  Future<void> _cancelarPartida() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    int horasRegraMulta = 4;

    try {
      final configDoc = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (configDoc.exists && configDoc.data()?['horasMultaCancelamento'] != null) {
        horasRegraMulta = (configDoc.data()?['horasMultaCancelamento'] as num).toInt();
      }
    } catch (e) {
      debugPrint("Aviso: Falha ao buscar configs globais, usando padrão de 4h: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    final DateTime dataDoJogo = (widget.jogo['dataHora'] as Timestamp).toDate();
    final int dHoras = dataDoJogo.difference(_obterHoraRealAgora()).inHours;
    final double valorTotal = (widget.jogo['valor'] ?? 0.0).toDouble();

    double multa = (dHoras < horasRegraMulta) ? 10.0 : 0.0;
    double valorEstorno = (valorTotal - multa).clamp(0, 9999);

    if (multa > 0) {
      final aceitouTaxa = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text("Taxa de Cancelamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            "Como faltam menos de $horasRegraMulta horas para a partida ($dHoras horas restantes), haverá a retenção de uma multa de R\$ ${multa.toStringAsFixed(2)}.\n\nVocê receberá um estorno de R\$ ${valorEstorno.toStringAsFixed(2)}.",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("VOLTAR", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("ESTOU CIENTE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      );

      if (aceitouTaxa != true) return;
    }

    final resultado = await _dialogConfirmarCancelamento(multa, valorEstorno);
    if (resultado == null || resultado['confirmado'] != true) return;

    final String motivoFinal = resultado['motivo'];
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference jogoRef = FirebaseFirestore.instance.collection("jogos").doc(widget.jogo['id']);
        DocumentReference userRef = FirebaseFirestore.instance.collection("usuarios").doc(uid);

        transaction.update(jogoRef, {
          "status": "cancelado",
          "canceladoEm": FieldValue.serverTimestamp(),
          "canceladoPor": "contratante",
          "motivoCancelamento": motivoFinal,
          "multaRetida": multa,
          "valorEstornado": valorEstorno,
        });

        transaction.update(userRef, {
          "saldo": FieldValue.increment(valorEstorno),
          "qtdDesistencias": FieldValue.increment(1)
        });

        // ✨ CORREÇÃO 1: Salvando o reembolso direto no extrato do usuário!
        DocumentReference extratoReembolso = userRef.collection('extrato').doc();
        transaction.set(extratoReembolso, {
          "id": extratoReembolso.id,
          "idUsuario": uid,
          "tipo": "estorno", // A aba financeira lê 'estorno' como verde (+)
          "valor": valorEstorno,
          "status": "concluido", 
          "descricao": multa > 0 ? "Reembolso Parcial (${widget.jogo['local']})" : "Reembolso Integral (${widget.jogo['local']})",
          "data": FieldValue.serverTimestamp(),
          "idJogo": widget.jogo['id'],
        });

        // ✨ CORREÇÃO 2: Salvando a multa no extrato!
        if (multa > 0) {
          DocumentReference extratoMulta = userRef.collection('extrato').doc();
          transaction.set(extratoMulta, {
            "id": extratoMulta.id,
            "idUsuario": uid,
            "tipo": "multa_cancelamento", // A aba financeira lê isso como vermelho/laranja (-)
            "status": "concluido",
            "valor": multa,
            "descricao": "Taxa de cancelamento (< ${horasRegraMulta}h)",
            "data": FieldValue.serverTimestamp(),
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
    final TextEditingController detalheController = TextEditingController();
    final motivos = ["Campo cancelou", "Time desistiu", "Problema pessoal", "Consegui outro goleiro", "Outro"];

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Motivo do Cancelamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  multa > 0 
                    ? "Multa confirmada: R\$ ${multa.toStringAsFixed(2)}"
                    : "Estorno integral de R\$ ${estorno.toStringAsFixed(2)} será realizado.",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                ...motivos.map((m) => RadioListTile<String>(
                  title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  value: m,
                  groupValue: motivoSelecionado,
                  onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                  activeColor: const Color(0xFF00E676),
                  contentPadding: EdgeInsets.zero,
                )),
                const SizedBox(height: 10),
                TextField(
                  controller: detalheController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Observação adicional (opcional)",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("VOLTAR", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                disabledBackgroundColor: Colors.white10
              ),
              onPressed: (motivoSelecionado == null) 
                ? null 
                : () => Navigator.pop(ctx, {
                    "confirmado": true,
                    "motivo": "$motivoSelecionado: ${detalheController.text}"
                  }), 
              child: const Text("CONFIRMAR"),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarOpcoes() {
    final dt = (widget.jogo['dataHora'] as Timestamp).toDate();
    final duracao = widget.jogo['duracao'] ?? 60;
    final fimPartida = dt.add(Duration(minutes: duracao));
    final agora = _obterHoraRealAgora();
    
    final bool jaIniciou = agora.isAfter(dt);
    final bool jaTerminou = agora.isAfter(fimPartida);
    final status = widget.jogo['status'];

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
          
          if (!jaIniciou)
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

          if (!jaTerminou)
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.redAccent),
              title: const Text("Cancelar Partida", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _cancelarPartida();
              },
            ),
          
          if (jaTerminou)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Text(
                "Esta partida já foi encerrada. Utilize as ações no card principal.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
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
    
    final String dataExibicao = widget.jogo['dataExibicao'] ?? "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}";
    final String horaExibicao = widget.jogo['horaExibicao'] ?? "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    
    final fimPartida = dt.add(Duration(minutes: duracao));
    final agora = _obterHoraRealAgora();
    final bool jaTerminou = agora.isAfter(fimPartida);
    
    final limitePagamento = fimPartida.add(const Duration(hours: 12));
    final restante = limitePagamento.difference(agora);
    final bool expirouPrazo = restante.isNegative;

    final bool precisaAvaliar = status == 'finalizado' && widget.jogo['avaliacaoGoleiro'] == null && widget.jogo['idGoleiro'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(13))
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: (status == 'aberto' || (status == 'fechado' && !jaTerminou)) ? _mostrarOpcoes : null,
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
                                "$dataExibicao às $horaExibicao",
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
                        _buildStatusBadge(status, jaTerminou),
                      ],
                    ),
                  ],
                ),
              ),

              if (jaTerminou && status == 'fechado' && !expirouPrazo)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: Colors.orangeAccent.withAlpha(26),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Ação necessária: O pagamento será liberado em ${restante.inHours}h ${(restante.inMinutes % 60).toString().padLeft(2, '0')}m.",
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              if (jaTerminou && status == 'fechado' && expirouPrazo)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: Colors.blueGrey.withAlpha(26),
                  child: Row(
                    children: const [
                      SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.blueGrey, strokeWidth: 2)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Prazo expirado. Processando liberação automática...",
                          style: TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              if (jaTerminou && status == 'fechado' && !expirouPrazo) 
                _buildBotoesAcao(),
              
              if (precisaAvaliar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      label: const Text("AVALIAR GOLEIRO", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.amber.withAlpha(100)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _mostrarModalAvaliacao(widget.jogo['idGoleiro']),
                    ),
                  ),
                ),
              
              if (_isLoading) 
                const LinearProgressIndicator(minHeight: 2, color: Color(0xFF00E676), backgroundColor: Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool jaTerminou) {
    String label = status.toUpperCase();
    Color color = Colors.grey;

    bool emAndamento = false;
    if (status == 'fechado') {
      final dt = (widget.jogo['dataHora'] as Timestamp).toDate();
      final fim = dt.add(Duration(minutes: widget.jogo['duracao'] ?? 60));
      final agora = DateTime.now();
      emAndamento = agora.isAfter(dt) && agora.isBefore(fim);
    }

    if (status == 'finalizado' && widget.jogo['finalizadoAutomaticamente'] == true) {
      label = "FINALIZADO (SISTEMA)";
      color = Colors.blueGrey;
    } else if (status == 'fechado' && jaTerminou) {
      label = "AGUARDANDO FINALIZAÇÃO";
      color = Colors.orangeAccent;
    } else if (status == 'fechado' && emAndamento) {
      label = "EM ANDAMENTO ⚽"; 
      color = Colors.amber; 
    } else if (status == 'contestado') {
      label = "EM DISPUTA";
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
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withAlpha(127)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildBotoesAcao() {
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
                  side: BorderSide(color: Colors.redAccent.withAlpha(127)),
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
}