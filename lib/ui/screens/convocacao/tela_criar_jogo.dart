import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'tela_selecao_tempo.dart';
import 'package:defendepramim/ui/screens/mapa_seletor_page.dart';

class TelaCriarJogo extends StatefulWidget {
  final Map<String, dynamic>? dados;
  final VoidCallback? onFinalizado;
  
  const TelaCriarJogo({super.key, this.dados, this.onFinalizado});

  @override
  State<TelaCriarJogo> createState() => _TelaCriarJogoState();
}

class _TelaCriarJogoState extends State<TelaCriarJogo> {
  // --- ESTILO ---
  final Color primaryColor = const Color(0xFF00E676);
  final Color surfaceColor = const Color(0xFF121212);

  // --- ESTADO DA PARTIDA ---
  DateTime? dataSelecionada;
  TimeOfDay? horarioSelecionado;
  int duracaoSelecionada = 60;
  String localSelecionado = "";
  String observacoes = "";
  String nivelGoleiro = "";
  String tipoQuadra = "";
  double valorJogo = 0.0;
  bool _processando = false;

  // --- VARIÁVEIS DINÂMICAS DO FIREBASE ---
  bool _carregandoConfig = true;
  int _horasAntecedencia = 2;
  int _tempoDeslocamentoMin = 30; 

  double _precoVarzea = 35.0;
  double _precoInter = 36.0;
  double _precoElite = 38.0;

  double _taxaAppVarzea = 5.0;
  double _taxaAppInter = 6.0;
  double _taxaAppElite = 8.0;

  String nomeQuadraSalvar = "";
  String enderecoRuaSalvar = "";

  int _horasMultaCancelamento = 12;
  double _valorMulta = 10.0;

  // 🟢 NOVAS VARIÁVEIS DE REQUISITO (MANTENDO SINCRONIA COM O ADMIN)
  int _reqExperientePartidas = 5;
  double _reqExperienteNota = 4.2;
  int _reqElitePartidas = 15;
  double _reqEliteNota = 4.5;

  // --- TRAVAS DOS NÍVEIS (REATIVAS DO ADMIN) ---
  bool _nivelLivreAtivo = true;
  bool _nivelInterAtivo = false; 
  bool _nivelEliteAtivo = false;
  StreamSubscription<DocumentSnapshot>? _configSubscription;

  final TextEditingController _cLoc = TextEditingController();
  final TextEditingController _cObs = TextEditingController();

  // --- GETTERS DE VALIDAÇÃO ---
  bool get dataOk => dataSelecionada != null && horarioSelecionado != null;
  bool get localOk => localSelecionado.isNotEmpty && latitudeJogo != null && longitudeJogo != null;
  bool get quadraOk => tipoQuadra.isNotEmpty;
  bool get nivelOk => nivelGoleiro.isNotEmpty;
  bool get tudoPronto => dataOk && localOk && quadraOk && nivelOk;
  
  double? latitudeJogo;
  double? longitudeJogo;

  @override
  void initState() {
    super.initState();
    _escutarConfiguracoesGlobais(); 
    if (widget.dados != null) carregarDadosEdicao();
  }

  @override
  void dispose() {
    _configSubscription?.cancel(); 
    _cLoc.dispose();
    _cObs.dispose();
    super.dispose();
  }

  // 🟢 ESCUTA EM TEMPO REAL
  void _escutarConfiguracoesGlobais() {
    _configSubscription = FirebaseFirestore.instance
        .collection('configuracoes')
        .doc('global')
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _horasAntecedencia = (d['horasAntecedencia'] ?? 2).toInt();
          _tempoDeslocamentoMin = (d['tempoDeslocamentoMinutos'] ?? 30).toInt();
          _precoVarzea = (d['precoVarzea'] ?? 35.0).toDouble();
          _precoInter = (d['precoInter'] ?? 36.0).toDouble();
          _precoElite = (d['precoElite'] ?? 38.0).toDouble();
          _taxaAppVarzea = (d['taxaAppVarzea'] ?? 5.0).toDouble();
          _taxaAppInter = (d['taxaAppInter'] ?? 6.0).toDouble();
          _taxaAppElite = (d['taxaAppElite'] ?? 8.0).toDouble();

          _horasMultaCancelamento = (d['horasMultaCancelamento'] ?? 12).toInt();
          _valorMulta = (d['valorMultaCancelamento'] ?? 10.0).toDouble();

          _nivelLivreAtivo = d['nivelLivreAtivo'] ?? true;
          _nivelInterAtivo = d['nivelInterAtivo'] ?? false;
          _nivelEliteAtivo = d['nivelEliteAtivo'] ?? false;

          // Requisitos Dinâmicos Injetados!
          _reqExperientePartidas = (d['reqExperientePartidas'] ?? 5).toInt();
          _reqExperienteNota = (d['reqExperienteNota'] ?? 4.2).toDouble();
          _reqElitePartidas = (d['reqElitePartidas'] ?? 15).toInt();
          _reqEliteNota = (d['reqEliteNota'] ?? 4.5).toDouble();

          _carregandoConfig = false;
        });
      }
    }, onError: (e) {
      debugPrint("Erro ao escutar configs globais: $e");
      if (mounted) setState(() => _carregandoConfig = false);
    });
  }

  void _showSuccessVisual(String mensagem, VoidCallback aoFinalizar) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
      Future.delayed(const Duration(milliseconds: 1500), () {
          // 🛡️ O ESCUDO: Verifica se o contexto deste dialog ainda existe!
          if (!ctx.mounted) { return; }

          if (Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
            aoFinalizar();
          }
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor..withAlpha(13)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, color: primaryColor, size: 70),
                const SizedBox(height: 16),
                Text(
                  mensagem,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void carregarDadosEdicao() {
    setState(() {
      localSelecionado = widget.dados!["local"] ?? "";
      observacoes = widget.dados!["observacoes"] ?? "";
      valorJogo = (widget.dados!["valor"] ?? 0.0).toDouble();
      nivelGoleiro = widget.dados!["nivelGoleiro"] ?? "";
      tipoQuadra = widget.dados!["tipoQuadra"] ?? "";

      _cLoc.text = localSelecionado;
      _cObs.text = observacoes;
      
      latitudeJogo = widget.dados!["latitude"];
      longitudeJogo = widget.dados!["longitude"];

      final dynamic durRaw = widget.dados!["duracao"];
      if (durRaw == null) {
        duracaoSelecionada = 60;
      } else {
        duracaoSelecionada = (durRaw is int && durRaw <= 5) ? durRaw * 60 : durRaw;
      }

      final Timestamp? ts = widget.dados!["dataHora"];
      if (ts != null) {
        final DateTime localDT = ts.toDate();
        dataSelecionada = DateTime(localDT.year, localDT.month, localDT.day);
        horarioSelecionado = TimeOfDay(hour: localDT.hour, minute: localDT.minute);
      }
    });
  }

  Future<DateTime> _obterHoraCertaServidor() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('temp_time').doc();
      await docRef.set({'hora': FieldValue.serverTimestamp()});
      final snap = await docRef.get();
      await docRef.delete();
      return (snap.get('hora') as Timestamp).toDate();
    } catch (e) {
      return DateTime.now();
    }
  }

  Future<String?> _verificarConflitoAgenda(DateTime inicioNovoJogo, int duracaoMinutos) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final fimNovoJogo = inicioNovoJogo.add(Duration(minutes: duracaoMinutos));

    final conflitos = await FirebaseFirestore.instance
        .collection('jogos')
        .where('idContratante', isEqualTo: uid)
        .where('status', whereIn: ['aberto', 'fechado']) 
        .get();

    for (var doc in conflitos.docs) {
      if (widget.dados != null && doc.id == widget.dados!["id"]) continue;

      DateTime inicioExistente = (doc['dataHora'] as Timestamp).toDate();
      int duracaoExMinutos = (doc['duracao'] is int) ? doc['duracao'] : 60;
      DateTime fimExistente = inicioExistente.add(Duration(minutes: duracaoExMinutos));
      
      String localEx = doc['local'] ?? "outro local";
      String horaEx = doc['horaExibicao'] ?? "--:--";

      bool precisaDeslocamento = localSelecionado.isEmpty || (localEx.toLowerCase() != localSelecionado.toLowerCase());
      int tempoExtra = precisaDeslocamento ? _tempoDeslocamentoMin : 0;

      DateTime inicioExComBuffer = inicioExistente.subtract(Duration(minutes: tempoExtra));
      DateTime fimExComBuffer = fimExistente.add(Duration(minutes: tempoExtra));

      if (inicioNovoJogo.isBefore(fimExComBuffer) && fimNovoJogo.isAfter(inicioExComBuffer)) {
        String durFormat = duracaoExMinutos >= 60 ? "${(duracaoExMinutos / 60).toStringAsFixed(1)}h" : "$duracaoExMinutos min";

        if (tempoExtra > 0) {
           return "Conflito! Você já tem convocação às $horaEx em '$localEx'. O sistema exige $_tempoDeslocamentoMin min de intervalo para deslocamento.";
        } else {
           return "Conflito de agenda! Você já tem convocação às $horaEx (Duração: $durFormat).";
        }
      }
    }
    return null;
  }

  Future<void> validarEProcessar() async {
    setState(() => _processando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _processando = false);
      return;
    }

    final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    double saldoEmConta = (userDoc.data()?['saldo'] ?? 0.0).toDouble();

    double valorNecessario = valorJogo;
    if (widget.dados != null) {
      double valorJaPago = (widget.dados!["valor"] ?? 0.0).toDouble();
      valorNecessario = valorJogo - valorJaPago;
    }

    setState(() => _processando = false);

    if (saldoEmConta < valorNecessario && valorNecessario > 0) {
      _modalRecargaRapida(saldoEmConta, valorNecessario);
    } else {
      _abrirResumoFinal(saldoEmConta);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          widget.dados != null ? "EDITAR JOGO" : "CONVOCAR",
          style: TextStyle(color: primaryColor, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2.0),
        ),
        centerTitle: true,
      ),
      body: _carregandoConfig || _processando
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 5),
                    _buildProgressBar(),
                    const SizedBox(height: 16), // Espaçamento reduzido

                    // 1. CABEÇA DA TELA ENXUTA
                    const Text(
                      "Quais são os detalhes da pelada?",
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1),
                    ),
                    const SizedBox(height: 16), // Espaçamento reduzido

                    // 2. MANTÉM OS DOIS PRIMEIROS CARDS INTEIROS
                    _cardModuloMaster(
                      titulo: dataOk 
    ? "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')} às ${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}" 
    : "Data e Hora",
                      subtitulo: dataOk ? "${(duracaoSelecionada / 60).toStringAsFixed(0)}h de jogo" : "Quando e duração?",
                      icone: CupertinoIcons.calendar,
                      concluido: dataOk,
                      onTap: _abrirModuloTempo,
                    ),

                    _cardModuloMaster(
                      titulo: localOk ? localSelecionado : "Local",
                      subtitulo: localOk ? (observacoes.isEmpty ? "Toque para alterar" : observacoes) : "Onde vai ser?",
                      icone: CupertinoIcons.location_solid,
                      concluido: localOk,
                      onTap: () async {
                        final resultado = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MapaSeletorPage()), 
                        );

                        if (resultado != null) {
                          setState(() {
                            nomeQuadraSalvar = resultado['nomeLocal'];
                            enderecoRuaSalvar = resultado['enderecoRua'];
                            
                            localSelecionado = "${resultado['nomeLocal']} (${resultado['enderecoRua']})";
                            _cLoc.text = localSelecionado;
                            
                            observacoes = resultado['obs']; 
                            _cObs.text = resultado['obs'];

                            latitudeJogo = resultado['lat'];
                            longitudeJogo = resultado['lng'];
                          });
                        }
                      },
                    ),

                    // 3. A GRANDE MUDANÇA: LADO A LADO!
                    Row(
                      children: [
                        Expanded(
                          child: _cardMini(
                            titulo: quadraOk ? _resumirTextoQuadra(tipoQuadra) : "Quadra",
                            icone: Icons.grass_outlined,
                            concluido: quadraOk,
                            onTap: _abrirSeletorTipoQuadra,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _cardMini(
                            titulo: nivelOk ? nivelGoleiro : "Nível",
                            icone: Icons.front_hand_rounded,
                            concluido: nivelOk,
                            onTap: _abrirSeletorNivelGoleiro,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    _barraAcaoFinal(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProgressBar() {
    double progresso = 0.00;
    if (dataOk) progresso += 0.25;
    if (localOk) progresso += 0.25;
    if (quadraOk) progresso += 0.25;
    if (nivelOk) progresso += 0.25;
    if (progresso > 1.0) progresso = 1.0;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progresso,
            backgroundColor: Colors.white..withAlpha(13),
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "${(progresso * 100).toInt()}% COMPLETO",
            style: TextStyle(color: primaryColor..withAlpha(153), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _cardModuloMaster({required String titulo, required String subtitulo, required IconData icone, required bool concluido, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14), // Padding reduzido de 16 para 14
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: concluido ? primaryColor.withAlpha(102) : Colors.white.withAlpha(13)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: concluido ? primaryColor.withAlpha(26) : Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, color: concluido ? primaryColor : Colors.white54, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 12)),
                  ],
                ),
              ),
              Icon(concluido ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: concluido ? primaryColor : Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  // Novo Card Menor para itens lado a lado
  Widget _cardMini({required String titulo, required IconData icone, required bool concluido, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: concluido ? primaryColor.withAlpha(102) : Colors.white.withAlpha(13)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: concluido ? primaryColor.withAlpha(26) : Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(10)),
              child: Icon(icone, color: concluido ? primaryColor : Colors.white54, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              titulo, 
              textAlign: TextAlign.center,
              style: TextStyle(color: concluido ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
  
  // Função auxiliar para evitar que o texto do tipo de quadra quebre a linha no Card Mini
  String _resumirTextoQuadra(String quadra) {
    if(quadra.contains("Futsal")) return "Futsal";
    if(quadra.contains("Society")) return "Society";
    if(quadra.contains("Campo")) return "Campo";
    if(quadra.contains("Areia")) return "Areia";
    return quadra;
  }

  Widget _barraAcaoFinal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("INVESTIMENTO", style: TextStyle(color: Colors.white..withAlpha(13), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(tudoPronto ? "R\$ ${valorJogo.toStringAsFixed(2)}" : "---", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(
            height: 50, // Aumentei um pouco a altura para ficar mais tocável
            width: 140, // Mais espaço para a palavra CONTINUAR
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tudoPronto ? primaryColor : const Color(0xFF333333),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), // Mais arredondado
              ),
              onPressed: tudoPronto ? validarEProcessar : null,
              child: const Text("CONTINUAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModuloTempo() async {
    setState(() => _processando = true);

    try {
      final DateTime agoraReal = await _obterHoraCertaServidor();
      setState(() => _processando = false);

      final res = await Navigator.push(
        context, 
        MaterialPageRoute(
          builder: (context) => TelaSelecaoTempo(
            dataInicial: dataSelecionada, 
            horaInicial: horarioSelecionado,
            
            validadorExterno: (dataHoraDesejada, duracaoMinutos) async {
              if (dataHoraDesejada.isBefore(agoraReal.add(Duration(hours: _horasAntecedencia)))) {
                return "A convocação exige $_horasAntecedencia horas de antecedência mínima!";
              }

              String? msgConflito = await _verificarConflitoAgenda(dataHoraDesejada, duracaoMinutos);
              if (msgConflito != null) {
                return msgConflito; 
              }

              return null;
            },
          ),
        ),
      );

      if (res != null && res is DadosTempo) {
        setState(() {
          dataSelecionada = res.data;
          horarioSelecionado = res.hora;
          duracaoSelecionada = res.duracao;

          if (nivelOk) {
            double precoBase = nivelGoleiro.contains("Elite") ? _precoElite : nivelGoleiro.contains("Inter") ? _precoInter : _precoVarzea;
            double horasJogadas = duracaoSelecionada / 60;
            valorJogo = precoBase * horasJogadas; 
          }
        });
      }
    } catch (e) {
      setState(() => _processando = false);
      _msgErro("Erro de sincronização. Verifique sua conexão e tente novamente.");
    }
  }

  void _abrirSeletorTipoQuadra() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      useSafeArea: true, 
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text("Tipo de Quadra", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _opcaoQuadra("Futsal (Quadra)"),
            _opcaoQuadra("Society (Sintético)"),
            _opcaoQuadra("Futebol de Campo (Grama)"),
            _opcaoQuadra("Areia / Beach Soccer"),
            const SizedBox(height: 10), 
          ],
        ),
      ),
    );
  }

  Widget _opcaoQuadra(String nome) {
    return ListTile(
      leading: Icon(
        nome.contains("Futsal") ? Icons.sports_volleyball :
        nome.contains("Society") ? Icons.grass :
        nome.contains("Areia") ? Icons.beach_access : Icons.stadium,
        color: primaryColor,
      ),
      title: Text(nome, style: const TextStyle(color: Colors.white)),
      onTap: () {
        setState(() {
          tipoQuadra = nome;
        });
        Navigator.pop(context);
      },
    );
  }

  void _abrirSeletorNivelGoleiro() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                children: [
                  Text("Nível do Goleiro", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text("Escolha o perfil de goleiro desejado para a partida", style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Divider(color: Colors.white10),

            _opcaoNivel(
              nome: "⚽ Livre (Aberto)",
              subtitulo: "Disponível para todos os goleiros cadastrados.",
              precoBase: _precoVarzea,
              bloqueado: !_nivelLivreAtivo,
              onTap: !_nivelLivreAtivo
                  ? () => _mostrarAvisoEmBreve("Livre")
                  : () {
                      setState(() {
                        nivelGoleiro = "Livre";
                        double horasJogadas = duracaoSelecionada / 60;
                        valorJogo = _precoVarzea * horasJogadas;
                      });
                      Navigator.pop(context);
                    },
            ),

            // 🟢 TEXTO AGORA É DINÂMICO BASEADO NO BANCO DE DADOS
            _opcaoNivel(
              nome: "🛡️ Experiente",
              subtitulo: "Requer $_reqExperientePartidas+ partidas e nota média ≥ ${_reqExperienteNota.toStringAsFixed(1)}★",
              precoBase: _precoInter,
              bloqueado: !_nivelInterAtivo,
              onTap: !_nivelInterAtivo
                  ? () => _mostrarAvisoEmBreve("Experiente")
                  : () {
                      setState(() {
                        nivelGoleiro = "Experiente";
                        double horasJogadas = duracaoSelecionada / 60;
                        valorJogo = _precoInter * horasJogadas;
                      });
                      Navigator.pop(context);
                    },
            ),

            // 🟢 TEXTO AGORA É DINÂMICO BASEADO NO BANCO DE DADOS
            _opcaoNivel(
              nome: "🥇 Elite / Paredão",
              subtitulo: "Requer $_reqElitePartidas+ partidas e nota média ≥ ${_reqEliteNota.toStringAsFixed(1)}★",
              precoBase: _precoElite,
              bloqueado: !_nivelEliteAtivo,
              onTap: !_nivelEliteAtivo
                  ? () => _mostrarAvisoEmBreve("Elite")
                  : () {
                      setState(() {
                        nivelGoleiro = "Elite";
                        double horasJogadas = duracaoSelecionada / 60;
                        valorJogo = _precoElite * horasJogadas;
                      });
                      Navigator.pop(context);
                    },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _opcaoNivel({
    required String nome,
    required String subtitulo,
    required double precoBase,
    required bool bloqueado,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      onTap: onTap,
      title: Row(
        children: [
          Text(
            nome,
            style: TextStyle(
              color: bloqueado ? Colors.white38 : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          if (bloqueado) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber..withAlpha(13), width: 0.8),
              ),
              child: const Text(
                "EM BREVE",
                style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitulo,
        style: TextStyle(color: bloqueado ? Colors.white24 : Colors.white54, fontSize: 11),
      ),
      trailing: Text(
        "R\$ ${precoBase.toStringAsFixed(2)}/h",
        style: TextStyle(
          color: bloqueado ? Colors.white24 : primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  void _mostrarAvisoEmBreve(String nivel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_clock, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Text("Nível $nivel", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          "Estamos em fase inicial de convocações!\n\nOs filtros de goleiros $nivel serão liberados automaticamente à medida que nossa comunidade de goleiros realizar partidas e acumular avaliações na plataforma.",
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ENTENDI", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _modalRecargaRapida(double saldoAtual, double valorNecessario) {
    double falta = valorNecessario - saldoAtual;
    TextEditingController recargaController = TextEditingController(text: falta.toStringAsFixed(2));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Saldo Insuficiente", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.dados == null ? "Faltam R\$ ${falta.toStringAsFixed(2)} para criar este jogo." : "Faltam R\$ ${falta.toStringAsFixed(2)} para cobrir a diferença desta edição.",
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: recargaController,
              autofocus: true, // 🚀 Já abre o teclado direto!
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center, // 🚀 Centraliza o dinheiro
              style: TextStyle(color: primaryColor, fontSize: 32, fontWeight: FontWeight.bold), // 🚀 Fonte gigante de Fintech
              decoration: InputDecoration(
                prefixText: "R\$ ",
                prefixStyle: const TextStyle(color: Colors.white54, fontSize: 20),
                filled: true,
                fillColor: Colors.black26,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryColor, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () async {
              double valor = double.tryParse(recargaController.text.replaceAll(',', '.')) ?? 0;
              if (valor <= 0) return;

              Navigator.pop(ctx);
              setState(() => _processando = true);

              try {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
                final extratoRef = userRef.collection('extrato').doc();

                await FirebaseFirestore.instance.runTransaction((transaction) async {
                  DocumentSnapshot snapshot = await transaction.get(userRef);
                  double saldoAtualizado = (snapshot.data() as Map<String, dynamic>?)?['saldo']?.toDouble() ?? 0.0;

                  transaction.update(userRef, {'saldo': saldoAtualizado + valor});
                  transaction.set(extratoRef, {
                    "id": extratoRef.id, "idUsuario": uid, "tipo": "entrada", "valor": valor,
                    "saldoAnterior": saldoAtualizado, "saldoAtual": saldoAtualizado + valor,
                    "descricao": widget.dados == null ? "Recarga via Convocação" : "Recarga para Edição",
                    "categoria": "recarga", "data": FieldValue.serverTimestamp(),
                  });
                });

                if (mounted) {
                  setState(() => _processando = false);
                  _showSuccessVisual("Saldo Adicionado!", () { validarEProcessar(); });
                }
              } catch (e) {
                if (mounted) setState(() => _processando = false);
                _msgErro("Erro ao recarregar: $e");
              }
            },
            child: const Text("RECARREGAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _abrirResumoFinal(double saldoAtual) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("CONFIRMAR CONVOCAÇÃO", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _itemResumo(Icons.calendar_today, "Data/Hora", "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')} às ${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}"),
            _itemResumo(Icons.place, "Local", localSelecionado),
            _itemResumo(Icons.grass, "Quadra", tipoQuadra),
            _itemResumo(Icons.bolt, "Nível", nivelGoleiro),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total a pagar:", style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text("R\$ ${valorJogo.toStringAsFixed(2)}", style: TextStyle(color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Colors.grey, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Cancelamentos com menos de $_horasMultaCancelamento horas da partida terão retenção de R\$ ${_valorMulta.toStringAsFixed(2)}.",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8), // Espaçamento entre os avisos
            
            // --- AVISO 2: REGRA DO CONTRATO ASSINADO (Novo!) ---
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: Colors.grey, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Após um goleiro aceitar o convite, a edição de local e horário será bloqueada.",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(ctx);
                  salvarNoFirebase();
                },
                child: const Text("CONFIRMAR E CRIAR JOGO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemResumo(IconData icone, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icone, color: Colors.grey, size: 18),
          const SizedBox(width: 10),
          Text("$label: ", style: const TextStyle(color: Colors.grey)),
          Expanded(child: Text(valor, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Future<void> salvarNoFirebase() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      setState(() => _processando = true);

      final DateTime dataHoraInicio = DateTime(
        dataSelecionada!.year, 
        dataSelecionada!.month, 
        dataSelecionada!.day, 
        horarioSelecionado!.hour, 
        horarioSelecionado!.minute
      );
      final DateTime dataHoraFim = dataHoraInicio.add(Duration(minutes: duracaoSelecionada));

      String nomeFinalQuadra = nomeQuadraSalvar.isNotEmpty 
          ? nomeQuadraSalvar 
          : localSelecionado.split('(')[0].trim();
          
      String enderecoFinalQuadra = enderecoRuaSalvar.isNotEmpty 
          ? enderecoRuaSalvar 
          : (localSelecionado.contains('(') ? localSelecionado.split('(')[1].replaceAll(')', '').trim() : '');
      
      String nomeBuscaQuadra = nomeFinalQuadra.toLowerCase().trim();
      String enderecoBuscaQuadra = enderecoFinalQuadra.toLowerCase().trim();

      String? idQuadraVinculada = widget.dados?["idQuadra"];

      if (idQuadraVinculada == null) {
        try {
          if (nomeBuscaQuadra.isNotEmpty) {
            final snapNome = await FirebaseFirestore.instance
                .collection('quadras')
                .where('nomeBusca', isEqualTo: nomeBuscaQuadra)
                .limit(1)
                .get();

            if (snapNome.docs.isNotEmpty) {
              idQuadraVinculada = snapNome.docs.first.id;
            }
          }

          if (idQuadraVinculada == null && latitudeJogo != null && longitudeJogo != null) {
            final snapCoords = await FirebaseFirestore.instance
                .collection('quadras')
                .where('latitude', isGreaterThanOrEqualTo: latitudeJogo! - 0.0005)
                .where('latitude', isLessThanOrEqualTo: latitudeJogo! + 0.0005)
                .get();

            for (var docQ in snapCoords.docs) {
              final dQ = docQ.data();
              double? lngQ = dQ['longitude']?.toDouble();
              if (lngQ != null && (lngQ - longitudeJogo!).abs() <= 0.0005) {
                idQuadraVinculada = docQ.id;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint("Aviso na checagem de quadras duplicadas: $e");
        }
      }

      final DocumentReference userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final DocumentReference jogoRef = widget.dados != null 
          ? FirebaseFirestore.instance.collection("jogos").doc(widget.dados!["id"]) 
          : FirebaseFirestore.instance.collection("jogos").doc();
          
      final DocumentReference extratoRef = userRef.collection('extrato').doc();
      
      final DocumentReference? novaQuadraRef = (widget.dados == null && idQuadraVinculada == null) 
          ? FirebaseFirestore.instance.collection('quadras').doc() 
          : null;

      if (novaQuadraRef != null) {
        idQuadraVinculada = novaQuadraRef.id;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot userSnap = await transaction.get(userRef);
        final dadosUsuario = userSnap.data() as Map<String, dynamic>?;
        
        double saldoAtualServidor = dadosUsuario?['saldo']?.toDouble() ?? 0.0;
        String nomeContratanteLogado = dadosUsuario?['nome'] ?? "Contratante";

        double valorAntigo = (widget.dados?["valor"] ?? 0.0).toDouble();
        double diferencaSaldo = widget.dados == null ? -valorJogo : valorAntigo - valorJogo;
        double saldoDepois = saldoAtualServidor + diferencaSaldo;

        if (saldoDepois < 0) throw Exception("Saldo insuficiente verificado no servidor.");

        String descricaoExtrato = "";
        if (widget.dados == null) {
          descricaoExtrato = "Convocação: $localSelecionado";
        } else {
          if (diferencaSaldo > 0) {
            descricaoExtrato = "Estorno (Edição): $localSelecionado";
          // ignore: curly_braces_in_flow_control_structures
          } else if (diferencaSaldo < 0) descricaoExtrato = "Diferença (Edição): $localSelecionado";
          // ignore: curly_braces_in_flow_control_structures
          else descricaoExtrato = "Ajuste de detalhes: $localSelecionado";
        }

        transaction.update(userRef, {"saldo": saldoDepois});

        if (diferencaSaldo != 0) {
          transaction.set(extratoRef, {
            "id": extratoRef.id, 
            "idUsuario": uid, 
            "idReferencia": jogoRef.id, 
            "tipo": diferencaSaldo > 0 ? "entrada" : "saida",
            "valor": diferencaSaldo.abs(), 
            "saldoAnterior": saldoAtualServidor, 
            "saldoAtual": saldoDepois,
            "descricao": descricaoExtrato, 
            "categoria": "jogo", 
            "data": FieldValue.serverTimestamp(),
          });
        }

        double taxaBaseFixa = nivelGoleiro.contains("Elite") 
            ? _taxaAppElite 
            : nivelGoleiro.contains("Inter") 
                ? _taxaAppInter 
                : _taxaAppVarzea;
                
        double horasJogadas = duracaoSelecionada / 60;
        double comissaoTotalDesseJogo = taxaBaseFixa * horasJogadas;
        double liquidoDoGoleiro = valorJogo - comissaoTotalDesseJogo;

        transaction.set(
            jogoRef,
            {
              "id": jogoRef.id, 
              "idQuadra": idQuadraVinculada, 
              "local": localSelecionado, 
              "dataHora": Timestamp.fromDate(dataHoraInicio), 
              "dataHoraFim": Timestamp.fromDate(dataHoraFim),
              "dataExibicao": "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')}",
              "horaExibicao": "${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}",
              "valor": valorJogo, 
              "status": widget.dados?["status"] ?? "aberto", 
              "idContratante": uid, 
              "nomeContratante": nomeContratanteLogado,
              "observacoes": observacoes, 
              "nivelGoleiro": nivelGoleiro, 
              "tipoQuadra": tipoQuadra, 
              "duracao": duracaoSelecionada,
              "criadoEm": widget.dados?["criadoEm"] ?? FieldValue.serverTimestamp(), 
              "editadoEm": FieldValue.serverTimestamp(),
              
              "localizacao": GeoPoint(latitudeJogo!, longitudeJogo!), 
              "latitude": latitudeJogo, 
              "longitude": longitudeJogo,
              
              "taxaAplicada": comissaoTotalDesseJogo,      
              "valorGoleiro": liquidoDoGoleiro,            
            },
            SetOptions(merge: true));

        if (novaQuadraRef != null) { 
          transaction.set(novaQuadraRef, {
            "id": novaQuadraRef.id,
            "nome": nomeFinalQuadra,      
            "endereco": enderecoFinalQuadra,  
            "nomeBusca": nomeBuscaQuadra,       
            "enderecoBusca": enderecoBuscaQuadra, 
            "observacoes": observacoes,
            "tipoQuadra": tipoQuadra,
            
            "localizacao": GeoPoint(latitudeJogo!, longitudeJogo!), 
            "latitude": latitudeJogo,
            "longitude": longitudeJogo,
            
            "aprovada": false, 
            "sugeridaPor": uid,
            "criadaEm": FieldValue.serverTimestamp(),
          });
        }
      });

      if (mounted) {
        _showSuccessVisual(widget.dados != null ? "Atualizado!" : "Publicado!", () {
          if (widget.onFinalizado != null) {
            widget.onFinalizado!();
          } else {
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _processando = false);
      _msgErro("Erro ao salvar: $e");
    }
  }

  void _msgErro(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent));
  }
}