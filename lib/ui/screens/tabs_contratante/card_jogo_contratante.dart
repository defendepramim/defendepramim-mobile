import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:defendepramim/ui/screens/convocacao/tela_criar_jogo.dart';
import 'package:defendepramim/services/push_notification_service.dart';
import 'package:defendepramim/services/notificacao_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:defendepramim/ui/widgets/modal_avaliacao_goleiro.dart';
import 'package:defendepramim/ui/screens/tela_chat_jogo.dart';
import 'package:defendepramim/ui/widgets/modal_perfil_publico.dart';

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
  int _horasPrazoPagamento = 12;

  @override
  void initState() {
    super.initState();
    PushNotificationService().inicializar();
    _sincronizarRelogio(); 
    _buscarRegrasAdmin(); 

    _verificarEProcessarExpiracao();

    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _verificarEProcessarExpiracao();
        setState(() {});
      }
    });
  }

  /// Expiração + estorno são feitos pelo job servidor `expirarJogosAbertos`.
  /// O cliente NÃO mexe em saldo. Só atualiza UI via stream do jogo.
  Future<void> _verificarEProcessarExpiracao() async {
    // no-op financeiro — servidor é a fonte da verdade
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

  Future<void> _buscarRegrasAdmin() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (snap.exists && snap.data()?['horasPagamentoAuto'] != null) {
        if (mounted) {
          setState(() {
            _horasPrazoPagamento = (snap.data()?['horasPagamentoAuto'] as num).toInt();
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar prazo no card: $e");
    }
  }

  DateTime _obterHoraRealAgora() => DateTime.now().add(_diferencaServidor);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  IconData _obterIconeQuadra(String tipo) {
    final t = tipo.toLowerCase();
    
    if (t.contains('futsal') || t.contains('quadra') || t.contains('piso')) {
      return Icons.sports_volleyball_outlined; 
    } else if (t.contains('beach') || t.contains('areia') || t.contains('sand')) {
      return Icons.beach_access_outlined; 
    } else if (t.contains('campo') || t.contains('estadio')) {
      return Icons.stadium_outlined; 
    }
    
    return Icons.grass_outlined; 
  }

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

  Future<void> _mostrarModalAvaliacao(String idGoleiro, String statusAtual) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ModalAvaliacaoGoleiro(
        idGoleiro: idGoleiro,
        idJogo: widget.jogo['id'],
        onContestarWO: _abrirModalContestacao,
        onSucessoAvaliacao: () async {
          _showSnackBar("Avaliação salva com sucesso!", cor: Colors.green);
          if (statusAtual == 'fechado') {
            await _pagarGoleiro();
          }
        },
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
                  value: m, groupValue: motivoSelecionado, activeColor: const Color(0xFF00E676), contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                )),
                const SizedBox(height: 10),
                const Divider(color: Colors.white10),
                const SizedBox(height: 10),
                TextField(
                  controller: detalheController, style: const TextStyle(color: Colors.white), maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Descreva detalhes do ocorrido...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13), filled: true, fillColor: Colors.black26,
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, disabledBackgroundColor: Colors.white10),
              child: const Text("ENVIAR CONTESTAÇÃO", style: TextStyle(color: Colors.white)),
            ),
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

    final String idGoleiro = widget.jogo['idGoleiro'] ?? '';
    if (idGoleiro.isEmpty) {
      _showSnackBar("Goleiro não encontrado para contestação.", cor: Colors.red);
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
          "autor": "contratante", "motivo": justificativa.trim(), "data": FieldValue.serverTimestamp(), "statusMediacao": "aguardando_goleiro",
        },
      });
      batch.update(contratanteRef, {"jogosContestados": FieldValue.increment(1)});
      await batch.commit();

      _showSnackBar("Contestação registrada. Nossa equipe analisará o caso.", cor: Colors.orange);

      final localFormatado = (widget.jogo['local'] ?? '').toString().split('(')[0].trim();
      await NotificacaoService().enviarNotificacao(
        idUsuarioDestino: idGoleiro, titulo: "Jogo em Disputa ⚠️",
        mensagem: "O contratante relatou um problema no jogo em $localFormatado. O repasse foi pausado até a resolução.",
        tipo: 'cancelou_jogo', 
      );
    } catch (e) {
      _showSnackBar("Erro ao processar contestação.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Pagamento ao goleiro — só no servidor (finalizarJogoContratante).
  Future<void> _pagarGoleiro() async {
    if (_isLoading) return;

    final idGoleiro = widget.jogo['idGoleiro'];
    final idJogo = widget.jogo['id'];

    if (idGoleiro == null || idJogo == null) {
      _showSnackBar("Dados do jogo incompletos para pagamento.", cor: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'southamerica-east1')
          .httpsCallable('finalizarJogoContratante');

      final result = await callable.call({
        'idJogo': idJogo,
        'idempotencyKey': const Uuid().v4(),
      });

      final data = result.data;
      int pagoCentavos = 0;
      if (data is Map && data['valorPagoCentavos'] != null) {
        pagoCentavos = (data['valorPagoCentavos'] as num).round();
      }

      final valorFmt = (pagoCentavos / 100).toStringAsFixed(2).replaceAll('.', ',');
      _showSnackBar("Pagamento liberado! O goleiro recebeu R\$ $valorFmt", cor: Colors.green);
    } on FirebaseFunctionsException catch (e) {
      debugPrint("Erro no pagamento: $e");
      _showSnackBar(e.message ?? "Erro ao processar pagamento.", cor: Colors.red);
    } catch (e) {
      debugPrint("Erro no pagamento: $e");
      _showSnackBar("Erro ao processar transação financeira.", cor: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelarPartida() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    int horasRegraMulta = 12;
    double valorRegraMulta = 10.0;

    try {
      final configDoc = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (configDoc.exists) {
        final dados = configDoc.data();
        if (dados?['horasMultaCancelamento'] != null) horasRegraMulta = (dados?['horasMultaCancelamento'] as num).toInt();
        if (dados?['valorMultaCancelamento'] != null) valorRegraMulta = (dados?['valorMultaCancelamento'] as num).toDouble();
      }
    } catch (e) {
      debugPrint("Aviso: Falha ao buscar configs globais, usando padrão: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    final DateTime dataDoJogo = (widget.jogo['dataHora'] as Timestamp).toDate();
    final int dHoras = dataDoJogo.difference(_obterHoraRealAgora()).inHours;
    final double valorTotal = (widget.jogo['valor'] ?? 0.0).toDouble();

    double multa = (dHoras < horasRegraMulta) ? valorRegraMulta : 0.0;
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
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent), SizedBox(width: 8),
              Text("Taxa de Cancelamento", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Text(
            "Como faltam menos de $horasRegraMulta horas para a partida ($dHoras horas restantes), haverá a retenção de uma multa de R\$ ${multa.toStringAsFixed(2)}.\n\nVocê receberá um estorno de R\$ ${valorEstorno.toStringAsFixed(2)}.",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("VOLTAR", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("CANCELA E PAGAR MULTA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      );
      if (aceitouTaxa != true) return;
    }

    final resultado = await _dialogConfirmarCancelamento(multa, valorEstorno);
    if (resultado == null || resultado['confirmado'] != true) return;

    final String motivoFinal = resultado['motivo']?.toString() ?? "Cancelado pelo contratante";
    setState(() => _isLoading = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'southamerica-east1')
          .httpsCallable('cancelarJogoContratante');

      final result = await callable.call({
        'idJogo': widget.jogo['id'],
        'motivo': motivoFinal,
        'idempotencyKey': const Uuid().v4(),
      });

      final data = result.data;
      int estornoCentavos = 0;
      int multaCentavos = 0;
      if (data is Map) {
        if (data['estornoCentavos'] != null) {
          estornoCentavos = (data['estornoCentavos'] as num).round();
        }
        if (data['multaCentavos'] != null) {
          multaCentavos = (data['multaCentavos'] as num).round();
        }
      }

      if (multaCentavos > 0) {
        _showSnackBar(
          "Cancelado. Estorno R\$ ${(estornoCentavos / 100).toStringAsFixed(2)} (multa R\$ ${(multaCentavos / 100).toStringAsFixed(2)}).",
          cor: Colors.orange,
        );
      } else {
        _showSnackBar(
          "Partida cancelada. Estorno de R\$ ${(estornoCentavos / 100).toStringAsFixed(2)}.",
          cor: Colors.green,
        );
      }
      // Push ao goleiro é feito pelo servidor
    } on FirebaseFunctionsException catch (e) {
      _showSnackBar(e.message ?? "Erro ao processar cancelamento.", cor: Colors.red);
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
                  multa > 0 ? "Multa confirmada: R\$ ${multa.toStringAsFixed(2)}" : "Estorno integral de R\$ ${estorno.toStringAsFixed(2)} será realizado.",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                ...motivos.map((m) => RadioListTile<String>(
                  title: Text(m, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  value: m, groupValue: motivoSelecionado, onChanged: (val) => setStateSB(() => motivoSelecionado = val),
                  activeColor: const Color(0xFF00E676), contentPadding: EdgeInsets.zero,
                )),
                const SizedBox(height: 10),
                TextField(
                  controller: detalheController, style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Observação adicional (opcional)", hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true, fillColor: Colors.black26, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("VOLTAR", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, disabledBackgroundColor: Colors.white10),
              onPressed: (motivoSelecionado == null) ? null : () => Navigator.pop(ctx, {"confirmado": true, "motivo": "$motivoSelecionado: ${detalheController.text}"}),
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 15),

            if (!jaIniciou && status == 'aberto')
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text("Editar Detalhes", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => TelaCriarJogo(dados: widget.jogo), fullscreenDialog: true));
                },
              ),

            if (!jaIniciou && status == 'fechado')
               const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white38, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "O goleiro já está confirmado. Não é possível alterar o local ou horário da partida.\nUse o chat para combinar detalhes.", 
                        style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
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
                child: Text("Esta partida já foi encerrada. Utilize as ações no card principal.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderGoleiro(
    String status,
    Color cor,
    bool jaTerminou, {
    bool expirouPrazo = false,
    int? notaGoleiro,
    bool finalizadoAutomaticamente = false,
  }) {
    String texto = "";
    Color corFundo = cor.withAlpha(15);
    Widget leadingIcon = Icon(Icons.info_outline, color: cor, size: 18);

    if (status == 'fechado' && !jaTerminou) {
      texto = "Goleiro confirmado para a pelada!";
    } else if (status == 'fechado' && jaTerminou && expirouPrazo) {
      // Prazo passou: job rotinaPagamentoAutomatico já deve ter pago (ou está a processar)
      texto = "Prazo encerrado · pagamento automático em andamento";
      leadingIcon = Icon(Icons.sync, color: cor, size: 18);
    } else if (status == 'fechado' && jaTerminou) {
      texto = "Partida encerrada. Libere o pagamento.";
    } else if (status == 'aberto') {
      if (jaTerminou) {
        // Job servidor (expirarJogosAbertos) ainda não processou — até ~15 min
        texto = "Aguardando estorno automático...";
      } else {
        texto = "Buscando goleiro na região...";
      }
      leadingIcon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(color: Colors.orangeAccent, strokeWidth: 2),
      );
    } else if (status == 'finalizado') {
      if (notaGoleiro == null) {
        texto = finalizadoAutomaticamente
            ? "Pagamento liberado automaticamente · avalie o goleiro"
            : "Pagamento liberado · avalie o goleiro";
      } else {
        texto = "Pagamento liberado com sucesso";
      }
      leadingIcon = Icon(Icons.check_circle, color: cor, size: 18);
    } else if (status == 'cancelado') {
      texto = "Partida cancelada";
      leadingIcon = Icon(Icons.cancel, color: cor, size: 18);
    } else if (status == 'contestado') {
      texto = "Partida em disputa no suporte";
      leadingIcon = Icon(Icons.warning_rounded, color: cor, size: 18);
    } else if (status == 'expirado') {
      final int? estornoC = (widget.jogo['valorEstornadoCentavos'] as num?)?.round();
      if (estornoC != null && estornoC > 0) {
        texto = "Expirou sem goleiro · estorno R\$ ${(estornoC / 100).toStringAsFixed(2)}";
      } else {
        texto = "Expirou sem goleiro · valor estornado";
      }
      leadingIcon = Icon(Icons.timer_off, color: cor, size: 18);
    }

    final String? idGoleiro = widget.jogo['idGoleiro'];

    if (idGoleiro != null && ['fechado', 'finalizado', 'contestado'].contains(status)) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('usuarios').doc(idGoleiro).get(),
        builder: (context, snapshot) {
          String nomeGoleiro = widget.jogo['nomeGoleiro'] ?? "Muralha";
          String? fotoUrl;

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data != null) {
              nomeGoleiro = data['nome'] ?? nomeGoleiro;
              fotoUrl = data['fotoUrl'];
            }
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: corFundo),
            child: Row(
              children: [
              InkWell(
                  onTap: () {
                    ModalPerfilPublico.mostrar(
                      context,
                      uid: idGoleiro, 
                      isGoleiro: true, 
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: cor.withAlpha(40),
                    backgroundImage: fotoUrl != null && fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
                    child: fotoUrl == null || fotoUrl.isEmpty ? Icon(Icons.person, color: cor, size: 16) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 1),
                      Text("Muralha: $nomeGoleiro", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                
                if (status == 'fechado' || status == 'finalizado' || status == 'contestado')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'fechado' && !jaTerminou) ...[
                        Icon(Icons.shield_outlined, color: cor, size: 18),
                        const SizedBox(width: 12),
                      ],
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TelaChatJogo(
                                idJogo: widget.jogo['id'].toString(), 
                                nomeDestinatario: nomeGoleiro,
                                dataHoraJogo: (widget.jogo['dataHora'] as Timestamp).toDate(),
                                duracaoJogo: (widget.jogo['duracao'] as num?)?.toInt() ?? 60, 
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cor.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.chat_bubble_outline, color: cor, size: 20),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('jogos')
                                    .doc(widget.jogo['id'].toString()) 
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
                                  
                                  final bool mensagemNaoLida = ultimaMsg['idRemetente'] != uid && 
                                      (ultimaMsg['lida'] == false || ultimaMsg['lida'] == null);

                                  if (mensagemNaoLida) {
                                    return Positioned(
                                      top: -2, right: -2,
                                      child: Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent, 
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFF1E1E1E), width: 1.5),
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
              ],
            ),
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: corFundo),
      child: Row(
        children: [
          leadingIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.jogo['status'] ?? 'aberto';
    final dt = (widget.jogo['dataHora'] as Timestamp).toDate();
    final duracao = widget.jogo['duracao'] ?? 60;
    final double valorBruto = (widget.jogo['valor'] ?? 0.0).toDouble();
    final String valorFormatado = valorBruto.toStringAsFixed(2).replaceAll('.', ',');

    final String dataExibicao = widget.jogo['dataExibicao'] ?? "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}";
    final String horaExibicao = widget.jogo['horaExibicao'] ?? "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

    final String tipoQuadra = widget.jogo['tipoQuadra'] ?? 'Não informado';
    final String nivel = widget.jogo['nivelGoleiro'] ?? widget.jogo['nivel'] ?? 'Não informado';
    final String obs = widget.jogo['observacoes']?.toString() ?? '';

    final fimPartida = dt.add(Duration(minutes: duracao));
    final agora = _obterHoraRealAgora();
    final bool jaTerminou = agora.isAfter(fimPartida);

    final limitePagamento = fimPartida.add(Duration(hours: _horasPrazoPagamento));
    final restante = limitePagamento.difference(agora);
    final bool expirouPrazo = restante.isNegative;

    final dynamic notaRaw = widget.jogo['avaliacaoGoleiro'];
    final int? notaGoleiro = notaRaw is num ? notaRaw.toInt() : null;
    final bool finalizadoAutomaticamente = widget.jogo['finalizadoAutomaticamente'] == true;

    // Botão de pagar: só enquanto o prazo manual ainda está aberto.
    // Depois do prazo / status finalizado: no máximo "avaliar" (pagamento já saiu ou sai pelo job).
    final bool podeAvaliarEPagar = status == 'fechado' && jaTerminou && !expirouPrazo;
    final bool podeAvaliarSo = status == 'finalizado' && notaGoleiro == null;
    final bool aguardandoAvaliacao = podeAvaliarEPagar || podeAvaliarSo;
    final bool jaAvaliou = status == 'finalizado' && notaGoleiro != null;

    String localFull = widget.jogo['local']?.toString() ?? 'Local não informado';

    // 🚀 Lógica Polida: Trata strings bizarras legadas e impede overflow
    String nomeArena = localFull;
    String enderecoArena = '';

    if (localFull.startsWith('{resultado')) {
      nomeArena = "Partida a definir";
      enderecoArena = "Aguardando atualização do local";
    } else if (localFull.contains('(')) {
      var parts = localFull.split('(');
      nomeArena = parts[0].trim();
      enderecoArena = parts.length > 1 ? parts[1].replaceAll(')', '').trim() : '';
    }

    final corStatus = _obterCorStatus(status, jaTerminou);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF161616), 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(15)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: (status == 'aberto' || (status == 'fechado' && !jaTerminou)) ? _mostrarOpcoes : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 4, width: double.infinity, color: corStatus),
              _buildHeaderGoleiro(
                status,
                corStatus,
                jaTerminou,
                expirouPrazo: expirouPrazo,
                notaGoleiro: notaGoleiro,
                finalizadoAutomaticamente: finalizadoAutomaticamente,
              ),
              
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(12)),
                          child: SvgPicture.asset(
                            'assets/field.svg', 
                            width: 28,
                            height: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 🚀 Flexible no Nome da Arena para evitar estouro horizontal
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nomeArena.toUpperCase(), 
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: -0.5), 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                enderecoArena.isNotEmpty ? enderecoArena : "Endereço não detalhado", 
                                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.2), 
                                maxLines: 2, 
                                overflow: TextOverflow.ellipsis,
                              ),
                              
                              if (obs.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Tooltip(
                                    message: obs,
                                    triggerMode: TooltipTriggerMode.tap, 
                                    decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(8)),
                                    textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline, color: Colors.white38, size: 12),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            obs,
                                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                                            maxLines: 1, 
                                            overflow: TextOverflow.ellipsis, 
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Preço protegido
                        Text(
                          "R\$ $valorFormatado", 
                          style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.w900, fontSize: 20),
                        ),
                      ],
                    ),

                    const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(color: Colors.white10, height: 1, thickness: 1)),

                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withAlpha(10))),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 🚀 Flexible Aplicado a todas as variáveis
                              Flexible(child: _buildInfoItem(Icons.calendar_today_outlined, dataExibicao)),
                              Flexible(child: _buildInfoItem(Icons.access_time, horaExibicao)),
                              Flexible(child: _buildInfoItem(Icons.timer_outlined, "${duracao}m")),
                            ],
                          ),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10, height: 1, thickness: 1)),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoItem(_obterIconeQuadra(tipoQuadra), tipoQuadra),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _buildInfoItem(Icons.star_border_outlined, nivel),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              if ((status == 'cancelado' || status == 'expirado') && widget.jogo['motivoCancelamento'] != null)
                _buildBarraAlerta(Icons.info_outline, widget.jogo['motivoCancelamento'].toString(), Colors.redAccent),

              if (jaTerminou && status == 'fechado' && !expirouPrazo)
                _buildBarraAlerta(Icons.timer_outlined, "Liberação automática em ${restante.inHours}h ${(restante.inMinutes % 60).toString().padLeft(2, '0')}m.", Colors.orangeAccent),

              if (jaTerminou && status == 'fechado' && expirouPrazo)
                _buildBarraAlerta(Icons.sync, "Prazo expirado. Processando liberação...", Colors.blueGrey, animado: true),

              if (aguardandoAvaliacao)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), 
                  child: SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.star_rounded, color: Colors.black, size: 24),
                      label: Text(
                        // Após prazo ou já finalizado pelo job: só avaliar — pagamento já liberado
                        podeAvaliarSo ? "AVALIAR GOLEIRO" : "AVALIAR E LIBERAR PAGAMENTO",
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 13)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => _mostrarModalAvaliacao(widget.jogo['idGoleiro'], status), 
                    ),
                  ),
                ),

              if (jaAvaliou)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Sua avaliação: ", style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
                      ...List.generate(5, (index) => Icon(
                        index < (notaGoleiro ?? 0) ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber, size: 20,
                      )),
                    ],
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

  Color _obterCorStatus(String status, bool jaTerminou) {
    if (status == 'aberto') return Colors.orangeAccent;
    if (status == 'fechado') return jaTerminou ? Colors.orangeAccent : const Color(0xFF00E676);
    if (status == 'finalizado') return Colors.blueAccent;
    if (status == 'contestado') return Colors.redAccent;
    return Colors.white24;
  }

  Widget _buildInfoItem(IconData icone, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, color: Colors.white54, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBarraAlerta(IconData icone, String texto, Color cor, {bool animado = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: cor.withAlpha(26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          animado 
            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: cor, strokeWidth: 2))
            : Icon(icone, color: cor, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}