import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'; 
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart'; 

import 'tela_selecao_tempo.dart';
import 'package:defendepramim/ui/screens/mapa_seletor_page.dart';
import 'package:defendepramim/core/dinheiro.dart';

class TelaCriarJogo extends StatefulWidget {
  final Map? dados;
  final VoidCallback? onFinalizado;
  
  const TelaCriarJogo({super.key, this.dados, this.onFinalizado});

  @override
  State createState() => _TelaCriarJogoState();
}

class _TelaCriarJogoState extends State<TelaCriarJogo> {
  final Color primaryColor = const Color(0xFF00E676);
  final Color surfaceColor = const Color(0xFF121212);

  DateTime? dataSelecionada;
  TimeOfDay? horarioSelecionado;
  int duracaoSelecionada = 60;
  String localSelecionado = "";
  String observacoes = "";
  String nivelGoleiro = "";
  String tipoQuadra = "";
  double valorJogo = 0.0;
  bool _processando = false;

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
  /// busca_nome | mapa_pin — só busca_nome entra na fila de aprovação admin
  String origemSelecaoQuadra = "mapa_pin";

  int _horasMultaCancelamento = 12;
  double _valorMulta = 10.0;

  int _reqExperientePartidas = 5;
  double _reqExperienteNota = 4.2;
  int _reqElitePartidas = 15;
  double _reqEliteNota = 4.5;

  bool _nivelLivreAtivo = true;
  bool _nivelInterAtivo = false; 
  bool _nivelEliteAtivo = false;
  StreamSubscription? _configSubscription;

  final TextEditingController _cLoc = TextEditingController();
  final TextEditingController _cObs = TextEditingController();

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
          _reqExperientePartidas = (d['reqExperientePartidas'] ?? 5).toInt();
          _reqExperienteNota = (d['reqExperienteNota'] ?? 4.2).toDouble();
          _reqElitePartidas = (d['reqElitePartidas'] ?? 15).toInt();
          _reqEliteNota = (d['reqEliteNota'] ?? 4.5).toDouble();
          _carregandoConfig = false;
        });
      }
    }, onError: (e) {
      if (mounted) setState(() => _carregandoConfig = false);
    });
  }

  void _showSuccessVisual(String mensagem, VoidCallback aoFinalizar) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
      Future.delayed(const Duration(milliseconds: 1500), () {
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
              border: Border.all(color: primaryColor.withAlpha(51)), 
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

  Future _obterHoraCertaServidor() async {
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

  Future _verificarConflitoAgenda(DateTime inicioNovoJogo, int duracaoMinutos) async {
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
           return "Conflito! Você já tem convocação às \(horaEx em '\)localEx'. O sistema exige $_tempoDeslocamentoMin min de intervalo para deslocamento.";
        } else {
           return "Conflito de agenda! Você já tem convocação às \(horaEx (Duração:\)durFormat).";
        }
      }
    }
    return null;
  }

  Future validarEProcessar() async {
    setState(() => _processando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _processando = false);
      return;
    }

    // 🚀 LÊ O SALDO OFICIAL DA NOVA COLEÇÃO CARTEIRAS (EM CENTAVOS)
    final carteiraDoc = await FirebaseFirestore.instance.collection('carteiras').doc(uid).get();
    int saldoEmCentavos = (carteiraDoc.data()?['saldoCentavos'] ?? 0);
    double saldoReal = Dinheiro.paraReal(saldoEmCentavos);

    // Edição: só cobra a diferença positiva (upgrade).
    // Downgrade (Elite→Livre) estorna no servidor — não bloqueia por "falta de saldo".
    double valorNecessario = valorJogo;
    if (widget.dados != null) {
      final dynamic pagoC = widget.dados!["pagoEmCentavos"];
      final double valorJaPago = pagoC is num
          ? Dinheiro.paraReal(pagoC.round())
          : (widget.dados!["valor"] as num?)?.toDouble() ?? 0.0;
      valorNecessario = valorJogo - valorJaPago;
    }

    if (!mounted) return;
    setState(() => _processando = false);

    if (saldoReal < valorNecessario && valorNecessario > 0) {
      _modalRecargaRapida(saldoReal, valorNecessario);
    } else {
      _abrirResumoFinal(saldoReal);
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
                    const SizedBox(height: 16),

                    const Text(
                      "Quais são os detalhes da pelada?",
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1),
                    ),
                    const SizedBox(height: 16),

                    // 🚀 CORREÇÃO DO BUG VISUAL: Adicionado o $ na interpolação das variáveis
                    _cardModuloMaster(
                      titulo: dataOk 
                        ? "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')} às ${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}" 
                        : "Data e Hora",
                      subtitulo: dataOk ? "${(duracaoSelecionada / 60).toStringAsFixed(0)}h de jogo" : "Quando e duração?",
                      icone: CupertinoIcons.calendar,
                      concluido: dataOk,
                      onTap: _abrirModuloTempo,
                    ),

                    // 🚀 CORREÇÃO DO BUG VISUAL: Removida a string mal formatada que gerava os cartões com {resultado}
                    _cardModuloMaster(
                      titulo: localOk ? localSelecionado.split(' (')[0] : "Local", // Exibe apenas o nome principal
                      subtitulo: localOk ? observacoes.isEmpty ? localSelecionado : observacoes : "Onde vai ser?",
                      icone: CupertinoIcons.location_solid,
                      concluido: localOk,
                      onTap: () async {
                        final resultado = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MapaSeletorPage()), 
                        );

                        if (!mounted) return;
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
                            origemSelecaoQuadra = (resultado['origemSelecao'] ?? 'mapa_pin').toString();
                          });
                        }
                      },
                    ),

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
            backgroundColor: Colors.white.withAlpha(13), 
            valueColor: AlwaysStoppedAnimation(primaryColor),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "${(progresso * 100).toInt()}% COMPLETO",
            style: TextStyle(color: primaryColor.withAlpha(153), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5), 
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
          padding: const EdgeInsets.all(14),
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
                    Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                Text("INVESTIMENTO", style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)), 
                const SizedBox(height: 4),
                Text(tudoPronto ? "R\$ ${valorJogo.toStringAsFixed(2)}" : "---", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(
            height: 50,
            width: 140,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tudoPronto ? primaryColor : const Color(0xFF333333),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      if (!mounted) return;
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

      if (!mounted) return;
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
      if (!mounted) return;
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

            _opcaoNivel(
              nome: "🛡️ Experiente",
              subtitulo: "Requer ${_reqExperientePartidas}+ partidas e nota média ≥ ${_reqExperienteNota.toStringAsFixed(1)}★",
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

            _opcaoNivel(
              nome: "🥇 Elite / Paredão",
              subtitulo: "Requer ${_reqElitePartidas}+ partidas e nota média ≥ ${_reqEliteNota.toStringAsFixed(1)}★",
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
                color: Colors.amber.withAlpha(51),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withAlpha(128), width: 0.8), 
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
              autofocus: true, 
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center, 
              style: TextStyle(color: primaryColor, fontSize: 32, fontWeight: FontWeight.bold), 
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
              // Recarga liberada para testes externos (Callable de teste; gateway PIX real entra depois)
              double valor = double.tryParse(recargaController.text.replaceAll(',', '.')) ?? 0;
              if (valor <= 0) return;

              Navigator.pop(ctx);
              setState(() => _processando = true);

              try {
                int valorCentavos = Dinheiro.paraCentavos(valor);
                String idempotencyKey = const Uuid().v4();

                final callable = FirebaseFunctions.instanceFor(region: 'southamerica-east1')
                    .httpsCallable('recarregarCarteira');
                await callable.call({
                  'valorCentavos': valorCentavos,
                  'idempotencyKey': idempotencyKey,
                });

                if (!mounted) return;
                setState(() => _processando = false);
                _showSuccessVisual("Saldo Adicionado!", () {
                  validarEProcessar();
                });
              } on FirebaseFunctionsException catch (e) {
                if (!mounted) return;
                setState(() => _processando = false);
                _msgErro(e.message ?? "Erro ao recarregar.");
              } catch (e) {
                if (!mounted) return;
                setState(() => _processando = false);
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
            _itemResumo(
              Icons.calendar_today,
              "Data/Hora",
              "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')} às ${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}",
            ),
            _itemResumo(Icons.place, "Local", localSelecionado.split(' (')[0]),
            _itemResumo(Icons.grass, "Quadra", tipoQuadra),
            _itemResumo(Icons.bolt, "Nível", nivelGoleiro),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total a pagar:", style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text(
                  "R\$ ${valorJogo.toStringAsFixed(2)}",
                  style: TextStyle(color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold),
                ),
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
            
            const SizedBox(height: 8), 
            
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

  /// Cria/edita jogo + cobrança ATÓMICA no servidor (criarEPagarJogo).
  /// Cliente não grava jogo nem mexe em saldo.
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
        horarioSelecionado!.minute,
      );
      final DateTime dataHoraFim = dataHoraInicio.add(Duration(minutes: duracaoSelecionada));

      final String nomeFinalQuadra =
          nomeQuadraSalvar.isNotEmpty ? nomeQuadraSalvar : localSelecionado.split('(')[0].trim();
      final String enderecoFinalQuadra = enderecoRuaSalvar.isNotEmpty
          ? enderecoRuaSalvar
          : (localSelecionado.contains('(')
              ? localSelecionado.split('(')[1].replaceAll(')', '').trim()
              : '');
      final String nomeBuscaQuadra = nomeFinalQuadra.toLowerCase().trim();
      final String enderecoBuscaQuadra = enderecoFinalQuadra.toLowerCase().trim();

      String? idQuadraVinculada = widget.dados?["idQuadra"]?.toString();

      // Resolução de quadra (não-financeiro) — pode ficar no cliente
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
            for (final docQ in snapCoords.docs) {
              final dQ = docQ.data();
              final lngQ = (dQ['longitude'] as num?)?.toDouble();
              if (lngQ != null && (lngQ - longitudeJogo!).abs() <= 0.0005) {
                idQuadraVinculada = docQ.id;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint("Aviso ao resolver quadra: $e");
        }
      }

      // Nova quadra sugerida (não-financeiro)
      // Regras:
      // 1) Se já existe aprovada com mesmo nomeBusca → reutiliza, não cria pendente
      // 2) Só cria pendente se origem foi busca por nome (não pin/endereço no mapa)
      if (widget.dados == null && idQuadraVinculada == null && latitudeJogo != null && longitudeJogo != null) {
        // Já aprovada com mesmo nome?
        if (nomeBuscaQuadra.isNotEmpty) {
          try {
            final jaAprovada = await FirebaseFirestore.instance
                .collection('quadras')
                .where('aprovada', isEqualTo: true)
                .where('nomeBusca', isEqualTo: nomeBuscaQuadra)
                .limit(1)
                .get();
            if (jaAprovada.docs.isNotEmpty) {
              idQuadraVinculada = jaAprovada.docs.first.id;
            }
          } catch (e) {
            debugPrint("Aviso ao checar quadra aprovada: $e");
          }
        }

        // Só fila admin se veio da busca por nome
        if (idQuadraVinculada == null && origemSelecaoQuadra == 'busca_nome') {
          final novaQuadraRef = FirebaseFirestore.instance.collection('quadras').doc();
          idQuadraVinculada = novaQuadraRef.id;
          await novaQuadraRef.set({
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
            "origemSelecao": "busca_nome",
            "sugeridaPor": uid,
            "criadaEm": FieldValue.serverTimestamp(),
          });
        }
      }

      final double taxaBaseFixa = nivelGoleiro.contains("Elite")
          ? _taxaAppElite
          : nivelGoleiro.contains("Inter")
              ? _taxaAppInter
              : _taxaAppVarzea;
      final double horasJogadas = duracaoSelecionada / 60;
      final double comissaoTotalDesseJogo = taxaBaseFixa * horasJogadas;
      final double liquidoDoGoleiro = valorJogo - comissaoTotalDesseJogo;

      final String dataExibicao =
          "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')}";
      final String horaExibicao =
          "${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}";

      final String? idJogoExistente = widget.dados?["id"]?.toString();
      final String idempotencyKey = const Uuid().v4();

      final callable = FirebaseFunctions.instanceFor(region: 'southamerica-east1')
          .httpsCallable('criarEPagarJogo');

      await callable.call({
        'idempotencyKey': idempotencyKey,
        if (idJogoExistente != null) 'idJogo': idJogoExistente,
        'jogo': {
          'local': localSelecionado,
          'valor': valorJogo,
          'nivelGoleiro': nivelGoleiro,
          'tipoQuadra': tipoQuadra,
          'duracao': duracaoSelecionada,
          'observacoes': observacoes,
          // Epoch ms = fuso-agnóstico (evita o servidor UTC interpretar ISO local como UTC)
          'dataHoraMs': dataHoraInicio.millisecondsSinceEpoch,
          'dataHoraFimMs': dataHoraFim.millisecondsSinceEpoch,
          'dataHora': dataHoraInicio.toUtc().toIso8601String(),
          'dataHoraFim': dataHoraFim.toUtc().toIso8601String(),
          'dataExibicao': dataExibicao,
          'horaExibicao': horaExibicao,
          'latitude': latitudeJogo,
          'longitude': longitudeJogo,
          'idQuadra': idQuadraVinculada,
          'taxaAplicada': comissaoTotalDesseJogo,
          'valorGoleiro': liquidoDoGoleiro,
          'taxaAplicadaCentavos': Dinheiro.paraCentavos(comissaoTotalDesseJogo),
          'valorGoleiroCentavos': Dinheiro.paraCentavos(liquidoDoGoleiro),
        },
      });

      if (!mounted) return;
      _showSuccessVisual(widget.dados != null ? "Atualizado!" : "Publicado!", () {
        if (widget.onFinalizado != null) {
          widget.onFinalizado!();
        } else {
          if (mounted) Navigator.pop(context);
        }
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      _msgErro(e.message ?? "Erro ao salvar jogo.");
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      _msgErro("Erro ao salvar: $e");
    }
  }

  void _msgErro(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent));
  }
}