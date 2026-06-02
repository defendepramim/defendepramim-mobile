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

  // --- ESTADO ---
  DateTime? dataSelecionada;
  TimeOfDay? horarioSelecionado;
  int duracaoSelecionada = 1;
  String localSelecionado = "";
  String observacoes = "";
  String nivelGoleiro = "";
  double valorJogo = 0.0;
  bool _processando = false;

  // ✨ VARIÁVEIS DINÂMICAS DO FIREBASE (Novas regras de Pricing Tierizado)
  bool _carregandoConfig = true;
  int _horasAntecedencia = 2;

  // 1️⃣ NOVAS VARIÁVEIS GLOBAIS DE PRICING (Valores fixos por hora)
  double _precoVarzea = 35.0;
  double _precoInter = 36.0;
  double _precoElite = 38.0;

  double _taxaAppVarzea = 5.0;
  double _taxaAppInter = 6.0;
  double _taxaAppElite = 8.0;

  // Variáveis para carimbar o Crowdsourcing do mapa
  String nomeQuadraSalvar = "";
  String enderecoRuaSalvar = "";

  final TextEditingController _cLoc = TextEditingController();
  final TextEditingController _cObs = TextEditingController();

  bool get dataOk => dataSelecionada != null && horarioSelecionado != null;
  bool get localOk => localSelecionado.isNotEmpty;
  bool get nivelOk => nivelGoleiro.isNotEmpty;
  bool get tudoPronto => dataOk && localOk && nivelOk;
  double? latitudeJogo;
  double? longitudeJogo;

  @override
  void initState() {
    super.initState();
    _buscarConfiguracoesGlobais().then((_) {
      if (widget.dados != null) carregarDadosEdicao();
    });
  }

  @override
  void dispose() {
    _cLoc.dispose();
    _cObs.dispose();
    super.dispose();
  }

  // 2️⃣ LEITURA DOS VALORES ATUALIZADOS DO FIREBASE
  Future<void> _buscarConfiguracoesGlobais() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (doc.exists) {
        final d = doc.data()!;
        _horasAntecedencia = (d['horasAntecedencia'] ?? 2).toInt();
        
        // Puxando os novos tiers de preço e lucro fixo
        _precoVarzea = (d['precoVarzea'] ?? 35.0).toDouble();
        _precoInter = (d['precoInter'] ?? 36.0).toDouble();
        _precoElite = (d['precoElite'] ?? 38.0).toDouble();

        _taxaAppVarzea = (d['taxaAppVarzea'] ?? 5.0).toDouble();
        _taxaAppInter = (d['taxaAppInter'] ?? 6.0).toDouble();
        _taxaAppElite = (d['taxaAppElite'] ?? 8.0).toDouble();
      }
    } catch (e) {
      debugPrint("Erro ao carregar configs globais, usando padrão. Erro: $e");
    } finally {
      if (mounted) setState(() => _carregandoConfig = false);
    }
  }

  void _showSuccessVisual(String mensagem, VoidCallback aoFinalizar) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1500), () {
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
              border: Border.all(color: primaryColor.withOpacity(0.5)),
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

  // --- LÓGICA DE DADOS ---

  void carregarDadosEdicao() {
    setState(() {
      localSelecionado = widget.dados!["local"] ?? "";
      observacoes = widget.dados!["observacoes"] ?? "";
      valorJogo = (widget.dados!["valor"] ?? 0.0).toDouble();
      nivelGoleiro = widget.dados!["nivelGoleiro"] ?? "";

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

  // --- PROCESSAMENTO E FINANCEIRO ---

  Future<void> validarEProcessar() async {
    setState(() => _processando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _processando = false);
      return;
    }

    final DateTime agoraReal = await _obterHoraCertaServidor();

    final DateTime jogoDT = DateTime(
      dataSelecionada!.year,
      dataSelecionada!.month,
      dataSelecionada!.day,
      horarioSelecionado!.hour,
      horarioSelecionado!.minute,
    );

    if (jogoDT.isBefore(agoraReal.add(Duration(hours: _horasAntecedencia)))) {
      setState(() => _processando = false);
      _msgErro("A convocação exige $_horasAntecedencia horas de antecedência mínima!");
      return;
    }

    final DateTime inicioNovoJogo = jogoDT;
    final DateTime fimNovoJogo = jogoDT.add(Duration(minutes: duracaoSelecionada));

    final conflitos = await FirebaseFirestore.instance
        .collection('jogos')
        .where('idContratante', isEqualTo: uid)
        .where('status', isEqualTo: 'aberto')
        .get();

    String? msgConflito;

    for (var doc in conflitos.docs) {
      if (widget.dados != null && doc.id == widget.dados!["id"]) continue;

      DateTime inicioExistente = (doc['dataHora'] as Timestamp).toDate();
      final dynamic duracaoRaw = doc['duracao'];
      int duracaoExMinutos = (duracaoRaw is int) ? duracaoRaw : 60;

      DateTime fimExistente = inicioExistente.add(Duration(minutes: duracaoExMinutos));
      String localEx = doc['local'] ?? "outro local";
      String horaEx = doc['horaExibicao'] ?? "--:--";

      if (inicioNovoJogo.isBefore(fimExistente) && fimNovoJogo.isAfter(inicioExistente)) {
        String duracaoFormatada = duracaoExMinutos >= 60
            ? "${(duracaoExMinutos / 60).toStringAsFixed(1)}h"
            : "$duracaoExMinutos min";

        msgConflito = "Conflito de agenda! Você já tem uma convocação às $horaEx im $localEx (Duração: $duracaoFormatada).";
        break;
      }
    }

    if (msgConflito != null) {
      setState(() => _processando = false);
      _msgErro(msgConflito);
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

  // --- INTERFACE PRINCIPAL ---
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
                    const SizedBox(height: 20),

                    Center(
                      child: Text(
                        "Quais são os\ndetalhes da pelada?",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _cardModuloMaster(
                      titulo: dataOk ? "${dataSelecionada!.day}/${dataSelecionada!.month} às ${horarioSelecionado!.format(context)}" : "Data, Início e Duração",
                      subtitulo: dataOk ? "${(duracaoSelecionada / 60).toStringAsFixed(0)}h de partida" : "Quando e quanto tempo?",
                      icone: CupertinoIcons.calendar,
                      concluido: dataOk,
                      onTap: _abrirModuloTempo,
                    ),

                    // 🗺️ CARD DE LOCAL TOTALMENTE DIRECIONADO PRO MAPA PREMIUM COM BUSCA
                    _cardModuloMaster(
                      titulo: localOk ? localSelecionado : "Local e Detalhes",
                      subtitulo: localOk ? (observacoes.isEmpty ? "Toque para alterar o local" : observacoes) : "Onde vai ser o jogo?",
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

                    _cardModuloMaster(
                      titulo: nivelOk ? "Goleiro $nivelGoleiro" : "Nível do Goleiro",
                      subtitulo: nivelOk ? "Requisito definido" : "Qual o nível do arqueiro?",
                      icone: Icons.front_hand_rounded,
                      concluido: nivelOk,
                      onTap: _abrirSeletorNivelGoleiro,
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
    if (dataOk) progresso += 0.34;
    if (localOk) progresso += 0.33;
    if (nivelOk) progresso += 0.33;
    if (progresso > 1.0) progresso = 1.0;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progresso,
            backgroundColor: Colors.white.withOpacity(0.05),
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "${(progresso * 100).toInt()}% COMPLETO",
            style: TextStyle(color: primaryColor.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: concluido ? primaryColor.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: concluido ? primaryColor.withOpacity(0.1) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, color: concluido ? primaryColor : Colors.white54, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
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

  Widget _barraAcaoFinal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("INVESTIMENTO", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(nivelOk ? "R\$ ${valorJogo.toStringAsFixed(2)}" : "---", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(
            height: 46,
            width: 125,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tudoPronto ? primaryColor : const Color(0xFF333333),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: tudoPronto ? validarEProcessar : null,
              child: const Text("CONTINUAR", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // 3️⃣ CÁLCULO DE PREÇO TIERIZADO (MÓDULO DE SELEÇÃO DE TEMPO)
  void _abrirModuloTempo() async {
    final res = await Navigator.push(context, MaterialPageRoute(builder: (context) => TelaSelecaoTempo(dataInicial: dataSelecionada, horaInicial: horarioSelecionado)));

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
  }

  void _abrirSeletorNivelGoleiro() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text("Selecione o Nível", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          _opcaoNivel("Várzea (Livre)", _precoVarzea),
          _opcaoNivel("Intermediário (Médio)", _precoInter),
          _opcaoNivel("Elite (Master)", _precoElite),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 3️⃣ CÁLCULO DE PREÇO TIERIZADO (MÓDULO DE SELEÇÃO DE NÍVEL)
  Widget _opcaoNivel(String nome, double precoBase) {
    return ListTile(
      title: Text(nome, style: const TextStyle(color: Colors.white)),
      trailing: Text("R\$ ${precoBase.toStringAsFixed(2)}/h", style: TextStyle(color: primaryColor)),
      onTap: () {
        setState(() {
          nivelGoleiro = nome;
          double horasJogadas = duracaoSelecionada / 60;
          valorJogo = precoBase * horasJogadas;
        });
        Navigator.pop(context);
      },
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
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Valor para adicionar", labelStyle: TextStyle(color: Colors.grey), prefixText: "R\$ ", enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))),
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
            _itemResumo(Icons.calendar_today, "Data/Hora", "${dataSelecionada!.day}/${dataSelecionada!.month} às ${horarioSelecionado!.format(context)}"),
            _itemResumo(Icons.place, "Local", localSelecionado),
            _itemResumo(Icons.timer, "Duração", "${(duracaoSelecionada / 60).toStringAsFixed(0)}h"),
            _itemResumo(Icons.bolt, "Nível", nivelGoleiro),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total a pagar:", style: TextStyle(color: Colors.grey, fontSize: 16)),
                Text("R\$ ${valorJogo.toStringAsFixed(2)}", style: TextStyle(color: primaryColor, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
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

  // 4️⃣ CALCULAR O LUCRO E SALVAR NO BANCO!
  Future<void> salvarNoFirebase() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      setState(() => _processando = true);

      final DateTime dataHoraInicio = DateTime(dataSelecionada!.year, dataSelecionada!.month, dataSelecionada!.day, horarioSelecionado!.hour, horarioSelecionado!.minute);
      final DateTime dataHoraFim = dataHoraInicio.add(Duration(minutes: duracaoSelecionada));

      final DocumentReference userRef = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final DocumentReference jogoRef = widget.dados != null ? FirebaseFirestore.instance.collection("jogos").doc(widget.dados!["id"]) : FirebaseFirestore.instance.collection("jogos").doc();
      final DocumentReference extratoRef = userRef.collection('extrato').doc();

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
          if (diferencaSaldo > 0) descricaoExtrato = "Estorno (Edição): $localSelecionado";
          else if (diferencaSaldo < 0) descricaoExtrato = "Diferença (Edição): $localSelecionado";
          else descricaoExtrato = "Ajuste de detalhes: $localSelecionado";
        }

        transaction.update(userRef, {"saldo": saldoDepois});

        if (diferencaSaldo != 0) {
          transaction.set(extratoRef, {
            "id": extratoRef.id, "idUsuario": uid, "idReferencia": jogoRef.id, "tipo": diferencaSaldo > 0 ? "entrada" : "saida",
            "valor": diferencaSaldo.abs(), "saldoAnterior": saldoAtualServidor, "saldoAtual": saldoDepois,
            "descricao": descricaoExtrato, "categoria": "jogo", "data": FieldValue.serverTimestamp(),
          });
        }

        // 💰 MATEMÁTICA DA COMISSÃO EM REAIS POR HORA
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
              "duracao": duracaoSelecionada,
              "criadoEm": widget.dados?["criadoEm"] ?? FieldValue.serverTimestamp(), 
              "editadoEm": FieldValue.serverTimestamp(),
              "latitude": latitudeJogo,
              "longitude": longitudeJogo,
              
              // Carimbando as novas métricas financeiras tierizadas fixas
              "taxaAplicada": comissaoTotalDesseJogo,      // O lucro real do app
              "valorGoleiro": liquidoDoGoleiro,             // O repasse limpo do goleiro
            },
            SetOptions(merge: true));

        // 🧠 CROWDSOURCING: Sugere a nova quadra para validação do Admin
        if (widget.dados == null) { 
          DocumentReference novaQuadraRef = FirebaseFirestore.instance.collection('quadras').doc();
          
          transaction.set(novaQuadraRef, {
            "id": novaQuadraRef.id,
            "nome": nomeQuadraSalvar,      
            "endereco": enderecoRuaSalvar,  
            "observacoes": observacoes,
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
          if (widget.onFinalizado != null) widget.onFinalizado!();
          else Navigator.pop(context);
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