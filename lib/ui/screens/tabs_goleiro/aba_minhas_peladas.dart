import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:defendepramim/services/push_notification_service.dart'; // Ajuste o caminho se necessário

class AbaMinhasPeladas extends StatefulWidget {
  const AbaMinhasPeladas({super.key});

  @override
  State<AbaMinhasPeladas> createState() => _AbaMinhasPeladasState();
}

class _AbaMinhasPeladasState extends State<AbaMinhasPeladas> {
  Timer? _timer;
  Duration _diferencaServidor = Duration.zero;
  bool _isLoading = false;
  final Color primaryColor = const Color(0xFF00E676);
  final Color surfaceColor = const Color(0xFF1E1E1E);

  @override
  void initState() {
    super.initState();
    
    // 🟢 LIGA O MOTOR DE NOTIFICAÇÕES
    PushNotificationService().inicializar();
    
    _sincronizarRelogio();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- 🛰️ UTILITÁRIOS DE TEMPO E FEEDBACK ---
  void _showSnackBar(String texto, {Color cor = Colors.blue}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sincronizarRelogio() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('temp_time').doc();
      await docRef.set({'hora': FieldValue.serverTimestamp()});
      final snap = await docRef.get();
      await docRef.delete();
      if (mounted) {
        final DateTime horaReal = (snap.get('hora') as Timestamp).toDate();
        setState(
          () => _diferencaServidor = horaReal.difference(DateTime.now()),
        );
      }
    } catch (_) {}
  }

  DateTime _obterHoraRealAgora() => DateTime.now().add(_diferencaServidor);

  // --- 🤖 ROBÔ DESCENTRALIZADO: AUTO-PAGAMENTO PELO APP DO GOLEIRO ---
  bool _verificandoPagamentos = false;

  Future<void> _cacadorDePagamentosAtrasados(List<QueryDocumentSnapshot> docs) async {
    if (_verificandoPagamentos) return;
    _verificandoPagamentos = true;

    final agora = _obterHoraRealAgora();

    for (var doc in docs) {
      final dados = doc.data() as Map<String, dynamic>;
      
      // Só olha para jogos que o goleiro jogou e estão travados no 'fechado'
      if (dados['status'] == 'fechado') {
        final dt = (dados['dataHora'] as Timestamp).toDate();
        final duracao = dados['duracao'] ?? 60;
        final limitePagamento = dt.add(Duration(minutes: duracao)).add(const Duration(hours: 12));

        // Se já passou das 12h, o app do goleiro força a transação!
        if (agora.isAfter(limitePagamento)) {
          await _forcarPagamentoAutomaticoGoleiro(doc.id);
        }
      }
    }
    _verificandoPagamentos = false;
  }

  Future<void> _forcarPagamentoAutomaticoGoleiro(String idJogo) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);
        DocumentSnapshot jogoSnap = await transaction.get(jogoRef);

        if (!jogoSnap.exists) return;
        final dadosAtuais = jogoSnap.data() as Map<String, dynamic>;

        // 🛡️ TRAVA DE SEGURANÇA ABSOLUTA: 
        // Se o contratante pagou um milissegundo antes, o status não é mais 'fechado'. O app aborta para não pagar dobrado.
        if (dadosAtuais['status'] != 'fechado') return;

        final double valorGoleiro = (dadosAtuais['valor'] ?? 0.0).toDouble();
        final String idGoleiro = dadosAtuais['idGoleiro'];

        DocumentReference goleiroRef = FirebaseFirestore.instance.collection("usuarios").doc(idGoleiro);

        // 1. Finaliza o jogo
        transaction.update(jogoRef, {
          "status": "finalizado",
          "pagoEm": FieldValue.serverTimestamp(),
          "finalizadoAutomaticamente": true 
        });

        // 2. Coloca o dinheiro no bolso do goleiro
        transaction.update(goleiroRef, {
          "saldo": FieldValue.increment(valorGoleiro),
          "atuadas": FieldValue.increment(1) // ✨ Redundância 2: O próprio goleiro resgatou após 12h
        });

        // 3. Gera o extrato de recebimento
        DocumentReference extratoGoleiro = goleiroRef.collection('extrato').doc();
        transaction.set(extratoGoleiro, {
          "id": extratoGoleiro.id,
          "tipo": "recebimento",
          "valor": valorGoleiro,
          "data": FieldValue.serverTimestamp(),
          "descricao": "Pelada: ${dadosAtuais['local']}",
          "idJogo": idJogo,
          "status": "concluido"
        });
      });
      
      debugPrint("🤖 Robô do Goleiro ativou e resgatou o dinheiro do jogo $idJogo!");
    } catch (e) {
      debugPrint("Erro no auto-pagamento pelo lado do goleiro: $e");
    }
  }

  String _formatarTempoRestante(DateTime dataJogo, int duracao) {
    final agora = _obterHoraRealAgora();
    final fim = dataJogo.add(Duration(minutes: duracao));
    if (agora.isAfter(dataJogo) && agora.isBefore(fim)) return "JOGO ROLANDO ⚽";
    final diff = dataJogo.difference(agora);
    if (diff.isNegative) return "Partida encerrada";
    if (diff.inHours > 0) {
      return "Faltam ${diff.inHours}h ${diff.inMinutes % 60}m";
    }
    return "Faltam ${diff.inMinutes} min!";
  }

  // --- ⚖️ LÓGICA DE MEDIAÇÃO E DEFESA ---
  Future<void> _abrirModalDefesa(String idJogo) async {
    final TextEditingController defesaController = TextEditingController();
    File? imagemSelecionada;
    final ImagePicker picker = ImagePicker();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          title: const Text(
            "Sua Defesa",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Explique o ocorrido. O suporte analisará sua versão.",
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: defesaController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Sua justificativa...",
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                InkWell(
                  onTap: () async {
                    final XFile? photo = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (photo != null) {
                      setStateModal(() => imagemSelecionada = File(photo.path));
                    }
                  },
                  child: Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: imagemSelecionada == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                color: Colors.white38,
                              ),
                              Text(
                                "Anexar Prova",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.file(
                              imagemSelecionada!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "CANCELAR",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (defesaController.text.length < 10) {
                  _showSnackBar(
                    "Detalhe melhor sua defesa.",
                    cor: Colors.orange,
                  );
                  return;
                }
                Navigator.pop(ctx);
                _executarDefesa(idJogo, defesaController.text);
              },
              child: const Text("ENVIAR DEFESA"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executarDefesa(String idJogo, String texto) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('jogos').doc(idJogo).update({
        'contestacao.statusMediacao': 'em_analise_suporte',
        'contestacao.respostaGoleiro': texto,
        'contestacao.respondidoEm': FieldValue.serverTimestamp(),
      });
      _showSnackBar("Defesa enviada com sucesso!", cor: Colors.green);
    } catch (e) {
      _showSnackBar("Erro ao enviar defesa.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

// ✨ NOVA LÓGICA FINANCEIRA BLINDADA POR TRANSACTION COM FALTAS
  Future<void> _aceitarContestacao(String idJogo) async {
    setState(() => _isLoading = true);
    
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // 1. Buscar dados da partida
        DocumentReference jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);
        DocumentSnapshot jogoSnap = await transaction.get(jogoRef);
        
        if (!jogoSnap.exists) return;
        final dadosJogo = jogoSnap.data() as Map<String, dynamic>;
        final double valorEstorno = (dadosJogo['valor'] ?? 0).toDouble();
        final String idContratante = dadosJogo['idContratante'];

        // ✨ A CORREÇÃO ESTÁ AQUI: Pegar o ID do goleiro para criar o goleiroRef
        final String? idGoleiro = dadosJogo['idGoleiro'];
        if (idGoleiro == null) return; // Segurança extra

        DocumentReference goleiroRef = FirebaseFirestore.instance.collection('usuarios').doc(idGoleiro);
        DocumentReference contratanteRef = FirebaseFirestore.instance.collection('usuarios').doc(idContratante);
        DocumentReference extratoRef = contratanteRef.collection('extrato').doc();

        // 2. Executar mutações no Jogo
        transaction.update(jogoRef, {
          'status': 'contestado_aceito',
          'contestacao.statusMediacao': 'resolvido_goleiro_aceitou',
          'contestacao.finalizadoEm': FieldValue.serverTimestamp(),
        });

        // 3. Devolver o dinheiro para o Contratante
        transaction.update(contratanteRef, {
          'saldo': FieldValue.increment(valorEstorno),
        });

        // ✨ 4. APLICAR A FALTA NO PERFIL DO GOLEIRO
        transaction.update(goleiroRef, {
          'faltas': FieldValue.increment(1),
        });

        // 5. Gerar extrato para o contratante
        transaction.set(extratoRef, {
          'id': extratoRef.id,
          'idReferencia': idJogo,
          'tipo': 'estorno_contestacao',
          'valor': valorEstorno,
          'descricao': 'Estorno: Contestação aceita pelo goleiro',
          'data': FieldValue.serverTimestamp(),
          'status': 'concluido',
        });
      });

      _showSnackBar("Contestação aceita. O valor foi devolvido ao contratante.", cor: Colors.green);
    } catch (e) {
      _showSnackBar("Erro ao processar estorno.");
      debugPrint("Erro na contestação: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- 🛠️ LÓGICA DE DESISTÊNCIA (CORRIGIDA E REPOSICIONADA) ---
  void _dialogoDesistencia(String idJogo, DateTime dataJogo) {
    final int diffHoras = dataJogo.difference(_obterHoraRealAgora()).inHours;
    final double multa = diffHoras < 4 ? 10.0 : 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Desistir do Jogo",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          multa > 0
              ? "⚠️ Uma multa de R\$ ${multa.toStringAsFixed(2)} será aplicada, pois faltam menos de 4h para o jogo."
              : "Confirmar desistência?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VOLTAR", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _executarDesistencia(idJogo, multa);
            },
            child: const Text("CONFIRMAR"),
          ),
        ],
      ),
    );
  }

  Future<void> _executarDesistencia(String idJogo, double multa) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);

    try {
      // Usamos um WriteBatch para garantir que tudo aconteça junto
      final batch = FirebaseFirestore.instance.batch();

      // 1. Referência do Jogo (Volta a ficar disponível para outros)
      final jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);

      batch.update(jogoRef, {
        'status': 'aberto',
        'idGoleiro': FieldValue.delete(),
        'nomeGoleiro': FieldValue.delete(),
        'desistentes': FieldValue.arrayUnion([uid]),
      });

      // 2. Se houver multa, criamos o registro no extrato
      if (multa > 0) {
        final extratoRef = FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .collection('extrato')
            .doc();

        batch.set(extratoRef, {
          "id": extratoRef.id,
          "idReferencia": idJogo,
          "tipo": "multa_desistencia",
          "valor": multa,
          "descricao": "Multa: Desistência < 4h",
          "data": FieldValue.serverTimestamp(),
          "status": "concluido",
        });

        final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
        batch.update(userRef, {'multasPendentes': FieldValue.increment(multa)});
      }

      await batch.commit(); // Executa todas as operações
      _showSnackBar("Desistência concluída.");
    } catch (e) {
      _showSnackBar("Erro ao processar desistência.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 🧱 INTERFACE E LISTA ---
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text(
            "Minha Agenda",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            indicatorColor: primaryColor,
            labelColor: primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: "AGENDA"),
              Tab(text: "HISTÓRICO"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAbaAgenda(),
            _buildAbaHistorico(),
          ],
        ),
      ),
    );
  }

  // --- ABA 1: AGENDA ---
  Widget _buildAbaAgenda() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jogos')
          .where('idGoleiro', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Erro: ${snapshot.error}"));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return _buildEmptyState();

        final agora = _obterHoraRealAgora();

        // Filtros 
        final acontecendo = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final dt = (data['dataHora'] as Timestamp).toDate();
          final fim = dt.add(Duration(minutes: data['duracao'] ?? 60));
          return data['status'] == 'fechado' && agora.isAfter(dt) && agora.isBefore(fim);
        }).toList();

        acontecendo.sort((a, b) => (a['dataHora'] as Timestamp).compareTo(b['dataHora'] as Timestamp));

        final proximos = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final dt = (data['dataHora'] as Timestamp).toDate();
          return data['status'] == 'fechado' && agora.isBefore(dt);
        }).toList();

        proximos.sort((a, b) {
          final DateTime dateA = (a['dataHora'] as Timestamp).toDate();
          final DateTime dateB = (b['dataHora'] as Timestamp).toDate();
          return dateA.compareTo(dateB); 
        });

        final emAnalise = docs.where((d) {
          return (d.data() as Map<String, dynamic>)['status'] == 'contestado';
        }).toList();

        final cancelados = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['status'] == 'cancelado' &&
                 data['canceladoPor'] == 'contratante' &&
                 data['arquivadoGoleiro'] != true; 
        }).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            if (_isLoading)
              const LinearProgressIndicator(
                color: Color(0xFF00E676),
                backgroundColor: Colors.transparent,
              ),

            if (acontecendo.isNotEmpty) ...[
              _headerSection("ROLANDO AGORA ⚽", primaryColor),
              ...acontecendo.map(
                (d) => _buildCardIdentico(
                  d.id,
                  d.data() as Map<String, dynamic>,
                  "ao_vivo",
                ),
              ),
            ],

            if (cancelados.isNotEmpty) ...[
              _headerSection("AVISOS DE CANCELAMENTO 📢", Colors.redAccent),
              ...cancelados.map(
                (d) => _buildCardCancelado(d.id, d.data() as Map<String, dynamic>),
              ),
            ],

            if (emAnalise.isNotEmpty) ...[
              _headerSection(
                "PENDÊNCIAS / CONTESTAÇÕES ⚠️",
                Colors.orangeAccent,
              ),
              ...emAnalise.map(
                (d) => _buildCardIdentico(
                  d.id,
                  d.data() as Map<String, dynamic>,
                  "analise",
                ),
              ),
            ],

            if (proximos.isNotEmpty) ...[
              _headerSection("PRÓXIMOS JOGOS", Colors.blueAccent),
              ...proximos.map(
                (d) => _buildCardIdentico(
                  d.id,
                  d.data() as Map<String, dynamic>,
                  "agenda",
                ),
              ),
            ],

            const SizedBox(height: 100),
          ],
        );
      },
    );
  }

  // --- ABA 2: HISTÓRICO ---
  Widget _buildAbaHistorico() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
        .collection('jogos')
        .where('idGoleiro', isEqualTo: uid)
        .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // ✨ O PULO DO GATO ACONTECE AQUI:
        // Assim que os dados chegam, soltamos o robô para caçar atrasos ANTES de montar a tela!
        _cacadorDePagamentosAtrasados(snapshot.data!.docs);

        final historico = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final status = data['status'];
          final contestacao = data['contestacao'] as Map<String, dynamic>?;
          
          bool concluido = status == 'finalizado' || status == 'concluido';
          
          bool canceladoArquivado = status == 'cancelado' && data['arquivadoGoleiro'] == true;

          final dt = (data['dataHora'] as Timestamp).toDate();
          final fimDaPartida = dt.add(Duration(minutes: data['duracao'] ?? 60));
          bool jaEncerrouNoRelogio = _obterHoraRealAgora().isAfter(fimDaPartida);

          bool emContestacao = status == 'contestado';
          bool aguardandoPagamento = status == 'fechado' && jaEncerrouNoRelogio;

          // NOVA LÓGICA DE CONTESTAÇÃO RESOLVIDA PARA APARECER AQUI
          bool contestacaoResolvida = status == 'contestado_aceito' || 
              (status == 'cancelado' && contestacao?['statusMediacao'] == 'resolvido_goleiro_aceitou');

          return concluido || 
                 canceladoArquivado || 
                 contestacaoResolvida || 
                 emContestacao || 
                 aguardandoPagamento;
        }).toList();

        if (historico.isEmpty) return _buildEmptyState();

        historico.sort((a, b) {
          final dataA = a['dataHora'] as Timestamp?;
          final dataB = b['dataHora'] as Timestamp?;
          if (dataA == null || dataB == null) return 0;
          return dataB.compareTo(dataA);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: historico.length,
          itemBuilder: (context, index) {
            final jogo = historico[index].data() as Map<String, dynamic>;
            return _buildCardHistorico(jogo);
          },
        );
      },
    );
  }

  Widget _buildCardHistorico(Map<String, dynamic> jogo) {
    final agora = _obterHoraRealAgora();
    final DateTime dtAbsoluta = (jogo['dataHora'] as Timestamp).toDate();
    final int duracao = jogo['duracao'] ?? 60;
    
    // ✨ Pega as Strings blindadas
    final String dataExibicao = jogo['dataExibicao'] ?? "${dtAbsoluta.day.toString().padLeft(2, '0')}/${dtAbsoluta.month.toString().padLeft(2, '0')}";
    final String horaExibicao = jogo['horaExibicao'] ?? "${dtAbsoluta.hour.toString().padLeft(2, '0')}:${dtAbsoluta.minute.toString().padLeft(2, '0')}";

    // ✨ Reconstruir o relógio
    DateTime dataAlvoReal;
    try {
      final partesData = dataExibicao.split('/');
      final partesHora = horaExibicao.split(':');
      dataAlvoReal = DateTime(
        dtAbsoluta.year,
        int.parse(partesData[1]),
        int.parse(partesData[0]),
        int.parse(partesHora[0]),
        int.parse(partesHora[1]),
      );
    } catch (e) {
      dataAlvoReal = dtAbsoluta;
    }

    final DateTime fimPartida = dataAlvoReal.add(Duration(minutes: duracao));
    
    // --- Lógica de Status Core ---
    final String status = jogo['status'] ?? '';
    final Map<String, dynamic>? contestacao = jogo['contestacao'] as Map<String, dynamic>?;
    final String statusMediacao = contestacao?['statusMediacao'] ?? '';
    
    // Estados da Partida
    final bool isContestacaoAceita = status == 'contestado_aceito' || statusMediacao == 'resolvido_goleiro_aceitou';
    final bool isContestadoPendente = status == 'contestado' && statusMediacao == 'aguardando_goleiro';
    final bool emAnaliseSuporte = statusMediacao == 'em_analise_suporte';
    final bool foiCancelado = status == 'cancelado' && !isContestacaoAceita;
    final bool pendenteLiberacao = status == 'fechado' && agora.isAfter(fimPartida);

    // --- Definição Visual ---
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
      // ✨ AQUI: Mostrando a string fixa no histórico!
      subTexto = "$dataExibicao às $horaExibicao";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isContestacaoAceita || isContestadoPendente) 
              ? corStatus.withOpacity(0.3) 
              : Colors.white.withOpacity(0.05)
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: corStatus.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(iconeStatus, color: corStatus, size: 20),
          ),
          const SizedBox(width: 15),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jogo['local'] ?? 'Arena',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  subTexto,
                  style: TextStyle(
                    color: (isContestacaoAceita || isContestadoPendente) ? corStatus : Colors.white54, 
                    fontSize: 11, 
                    fontWeight: (isContestacaoAceita || isContestadoPendente) ? FontWeight.bold : FontWeight.normal
                  ),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "R\$ ${jogo['valor']}",
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
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rotuloStatus,
                  style: TextStyle(color: corStatus, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardCancelado(String id, Map<String, dynamic> jogo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "JOGO CANCELADO",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                onPressed: () {
                  FirebaseFirestore.instance.collection('jogos').doc(id).update(
                    {'arquivadoGoleiro': true},
                  );
                },
              ),
            ],
          ),
          Text(
            "A pelada na ${jogo['local']} foi cancelada pelo contratante.",
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          if (jogo['motivoCancelamento'] != null) ...[
            const SizedBox(height: 8),
            Text(
              "Motivo: ${jogo['motivoCancelamento']}",
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          const Text(
            "Nenhum jogo na agenda",
            style: TextStyle(color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _headerSection(String t, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Text(
      t,
      style: TextStyle(
        color: c,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _buildCardIdentico(String id, Map<String, dynamic> jogo, String cat) {
    // 1. Pega o Timestamp antigo só para garantir o ano
    final DateTime dtAbsoluta = (jogo['dataHora'] as Timestamp).toDate();
    final String status = jogo['status'] ?? '';
    final bool isContestado = status == 'contestado';
    final String statusMediacao = jogo['contestacao']?['statusMediacao'] ?? '';

    // ✨ 2. Pega as Strings blindadas
    final String dataExibicao = jogo['dataExibicao'] ?? "${dtAbsoluta.day.toString().padLeft(2, '0')}/${dtAbsoluta.month.toString().padLeft(2, '0')}";
    final String horaExibicao = jogo['horaExibicao'] ?? "${dtAbsoluta.hour.toString().padLeft(2, '0')}:${dtAbsoluta.minute.toString().padLeft(2, '0')}";

    // ✨ 3. Reconstruir o relógio
    DateTime dataAlvoReal;
    try {
      final partesData = dataExibicao.split('/');
      final partesHora = horaExibicao.split(':');
      dataAlvoReal = DateTime(
        dtAbsoluta.year,
        int.parse(partesData[1]),
        int.parse(partesData[0]),
        int.parse(partesHora[0]),
        int.parse(partesHora[1]),
      );
    } catch (e) {
      dataAlvoReal = dtAbsoluta;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isContestado
              ? Colors.redAccent.withOpacity(0.4)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            if (isContestado)
              Container(
                width: double.infinity,
                color: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  "PARTIDA EM CONTESTAÇÃO",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          jogo['local'] ?? 'Arena',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "R\$ ${jogo['valor']}",
                            style: TextStyle(
                              color: isContestado
                                  ? Colors.white38
                                  : primaryColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                          if (isContestado)
                            const Text(
                              "RETIDO",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  if (isContestado) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "O CONTRATANTE ALEGOU:",
                            style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "${jogo['contestacao']?['motivo']}",
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (statusMediacao == 'aguardando_goleiro')
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _aceitarContestacao(id),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white60,
                                side: const BorderSide(color: Colors.white12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text("ACEITAR", style: TextStyle(fontSize: 11)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _abrirModalDefesa(id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text("DEFENDER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    else
                      const Center(
                        child: Text("⏳ EM ANÁLISE PELO SUPORTE", style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ] else ...[
                    Row(
                      children: [
                        // ✨ AQUI: Usando a data correta no cronômetro
                        _infoBadge(
                          Icons.access_time,
                          _formatarTempoRestante(dataAlvoReal, jogo['duracao'] ?? 60),
                          cat == "ao_vivo" ? primaryColor : Colors.grey,
                        ),
                        const SizedBox(width: 15),
                        // ✨ AQUI: Usando as strings fixas na exibição
                        _infoBadge(
                          Icons.calendar_month,
                          "$dataExibicao às $horaExibicao",
                          Colors.grey,
                        ),
                      ],
                    ),
                    if (cat == "agenda") ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          // ✨ AQUI: Calculando multa de desistência com a hora CERTA
                          onPressed: () => _dialogoDesistencia(id, dataAlvoReal),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("DESISTIR DA PARTIDA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text, Color color) => Row(
    children: [
      Icon(icon, color: color.withOpacity(0.7), size: 14),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}