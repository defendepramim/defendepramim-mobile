import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'tela_selecao_tempo.dart';

class TelaCriarJogo extends StatefulWidget {
  final Map<String, dynamic>? dados;
  final VoidCallback?
  onFinalizado; // <-- O '?' deixa opcional para não quebrar outros arquivos

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

  bool get dataOk => dataSelecionada != null && horarioSelecionado != null;
  bool get localOk => localSelecionado.isNotEmpty;
  bool get nivelOk => nivelGoleiro.isNotEmpty;
  bool get tudoPronto => dataOk && localOk && nivelOk;

  @override
  void initState() {
    super.initState();
    if (widget.dados != null) carregarDadosEdicao();
  }

  void _showSuccessVisual(String mensagem, VoidCallback aoFinalizar) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Auto-fecha após 1.5 segundos
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
            aoFinalizar();
          }
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryColor.withOpacity(0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, color: primaryColor, size: 80),
                const SizedBox(height: 20),
                Text(
                  mensagem,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
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

    // AJUSTE AQUI: 
    // Se o que vier do banco for <= 5, provavelmente é o formato antigo (horas).
    // Se for > 5, já deve ser minutos. Se for nulo, usamos 60.
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
      horarioSelecionado = TimeOfDay(
        hour: localDT.hour,
        minute: localDT.minute,
      );
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

  // 1. Criar o DateTime do jogo
  final DateTime jogoDT = DateTime(
    dataSelecionada!.year,
    dataSelecionada!.month,
    dataSelecionada!.day,
    horarioSelecionado!.hour,
    horarioSelecionado!.minute,
  );

  // Validação de 2 horas de antecedência
  if (jogoDT.isBefore(agoraReal.add(const Duration(hours: 2)))) {
    setState(() => _processando = false);
    _msgErro("A convocação exige 2 horas de antecedência mínima!");
    return;
  }

  // --- AJUSTE AQUI: Padronização para MINUTOS ---
  final DateTime inicioNovoJogo = jogoDT;
  // Assumindo que duracaoSelecionada venha em minutos (ex: 60, 90, 120)
  final DateTime fimNovoJogo = jogoDT.add(
    Duration(minutes: duracaoSelecionada), 
  );

  final conflitos = await FirebaseFirestore.instance
      .collection('jogos')
      .where('idContratante', isEqualTo: uid)
      .where('status', isEqualTo: 'aberto')
      .get();

  String? msgConflito;

  for (var doc in conflitos.docs) {
    if (widget.dados != null && doc.id == widget.dados!["id"]) continue;

    DateTime inicioExistente = (doc['dataHora'] as Timestamp).toDate();
    
    // --- SEGURANÇA DE TIPAGEM E PADRÃO ---
    final dynamic duracaoRaw = doc['duracao'];
    // Se no banco estiver como horas (ex: 1), multiplicamos por 60. 
    // Se já estiver como minutos (ex: 60), mantemos.
    // DICA: O ideal é que você decida HOJE se o banco salva minutos ou horas.
    // Vamos assumir MINUTOS para o futuro:
    int duracaoExMinutos = (duracaoRaw is int) ? duracaoRaw : 60; 

    DateTime fimExistente = inicioExistente.add(Duration(minutes: duracaoExMinutos));
    String localEx = doc['local'] ?? "outro local";
    String horaEx = doc['horaExibicao'] ?? "--:--";

    // Lógica de Sobreposição (Intervalo Aberto)
    if (inicioNovoJogo.isBefore(fimExistente) &&
        fimNovoJogo.isAfter(inicioExistente)) {
      
      String duracaoFormatada = duracaoExMinutos >= 60 
          ? "${(duracaoExMinutos / 60).toStringAsFixed(1)}h" 
          : "$duracaoExMinutos min";

      msgConflito =
          "Conflito de agenda! Você já tem uma convocação às $horaEx no $localEx (Duração: $duracaoFormatada).";
      break;
    }
  }

  if (msgConflito != null) {
    setState(() => _processando = false);
    _msgErro(msgConflito);
    return;
  }

  // 2. Verificação de Saldo (Mantido original)
  final userDoc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(uid)
      .get();
      
  double saldoEmConta = (userDoc.data()?['saldo'] ?? 0.0).toDouble();

  double valorNecessario = valorJogo;
  if (widget.dados != null) {
    double valorJaPago = (widget.dados!["valor"] ?? 0.0).toDouble();
    valorNecessario = valorJogo - valorJaPago;
  }

  setState(() => _processando = false);

  if (saldoEmConta < valorNecessario && valorNecessario > 0) {
    _modalRecargaRapida(saldoEmConta, valorJogo);
  } else {
    _abrirResumoFinal(saldoEmConta);
  }
}

  // --- INTERFACE PRINCIPAL ---
  @override
  Widget build(BuildContext context) {
    // CORREÇÃO: Removi a variável não utilizada e movi padrões para o tema local
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        // O Flutter já coloca a seta de voltar automática se houver uma rota anterior
        title: Text(
          widget.dados != null ? "EDITAR JOGO" : "CONVOCAR",
          style: TextStyle(
            color: primaryColor,
            fontSize: 13, // Diminuí um pouco
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
      ),
      body: _processando
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _buildProgressBar(),
                    const SizedBox(height: 30),

                    // Texto de Destaque para substituir o que estava em desuso
                    Center(
                      // <-- Garante que o widget esteja no meio da largura da tela
                      child: Text(
                        "Quais são os\ndetalhes da pelada?",
                        textAlign: TextAlign
                            .center, // <-- Centraliza as linhas entre si
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _cardModuloMaster(
  titulo: dataOk
      ? "${dataSelecionada!.day}/${dataSelecionada!.month} às ${horarioSelecionado!.format(context)}"
      : "Data, Início e Duração",
  subtitulo: dataOk
      ? "${(duracaoSelecionada / 60).toStringAsFixed(0)}h de partida" // Divida por 60 aqui!
      : "Quando e quanto tempo?",
  icone: CupertinoIcons.calendar,
  concluido: dataOk,
  onTap: _abrirModuloTempo,
),

                    _cardModuloMaster(
                      titulo: localOk ? localSelecionado : "Local e Detalhes",
                      subtitulo: localOk
                          ? (observacoes.isEmpty
                                ? "Sem observações"
                                : observacoes)
                          : "Onde vai ser o jogo?",
                      icone: CupertinoIcons.location_solid,
                      concluido: localOk,
                      onTap: _abrirSeletorLocal,
                    ),

                    _cardModuloMaster(
                      titulo: nivelOk
                          ? "Goleiro $nivelGoleiro"
                          : "Nível do Goleiro",
                      subtitulo: nivelOk
                          ? "Requisito definido"
                          : "Qual o nível do arqueiro?",
                      icone: Icons.front_hand_rounded,
                      concluido: nivelOk,
                      onTap: _abrirSeletorNivelGoleiro,
                    ),

                    const SizedBox(height: 30),
                    _barraAcaoFinal(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  // Widget novo para dar o tchan de UX
  Widget _buildProgressBar() {
    double progresso = 0.00;
    if (dataOk) progresso += 0.31;
    if (localOk) progresso += 0.32;
    if (nivelOk) progresso += 0.32;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progresso,
            backgroundColor: Colors.white.withOpacity(0.05), // Mais sutil
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            minHeight: 4, // Mais fina fica mais elegante
          ),
        ),
        const SizedBox(height: 6),
        // Texto bem pequeno e com opacidade para não gritar na tela
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "${(progresso * 100).toInt()}% COMPLETO",
            style: TextStyle(
              color: primaryColor.withOpacity(0.6),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // --- COMPONENTES DE UI ---

  Widget _cardModuloMaster({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required bool concluido,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: concluido
                  ? primaryColor.withOpacity(0.4)
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: concluido
                      ? primaryColor.withOpacity(0.1)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icone,
                  color: concluido ? primaryColor : Colors.white54,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                concluido
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: concluido ? primaryColor : Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraAcaoFinal() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "INVESTIMENTO",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nivelOk ? "R\$ ${valorJogo.toStringAsFixed(2)}" : "---",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 50,
            width: 130,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tudoPronto
                    ? primaryColor
                    : const Color(0xFF333333),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: tudoPronto ? validarEProcessar : null,
              child: const Text(
                "CONTINUAR",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MÉTODOS DE APOIO (MODAIS E SELETORES) ---

  void _abrirModuloTempo() async {
    // 1. REMOVEMOS o 'const' e PASSAMOS as variáveis atuais
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TelaSelecaoTempo(
          dataInicial: dataSelecionada, // Passa a data que já foi escolhida
          horaInicial: horarioSelecionado, // Passa a hora que já foi escolhida
        ),
      ),
    );

    if (res != null && res is DadosTempo) {
      setState(() {
  dataSelecionada = res.data;
  horarioSelecionado = res.hora;
  duracaoSelecionada = res.duracao; // Aqui recebe 60 ou 120

  if (nivelOk) {
    double p = nivelGoleiro.contains("Elite") ? 38.0 : nivelGoleiro.contains("Inter") ? 36.0 : 35.0;
    // CALCULE ASSIM:
    valorJogo = p * (duracaoSelecionada / 60); 
  }
});
    }
  }

  void _abrirSeletorLocal() {
    TextEditingController cLoc = TextEditingController(text: localSelecionado);
    TextEditingController cObs = TextEditingController(text: observacoes);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Detalhes do Local",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: cLoc,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "Nome do Local"),
            ),
            TextField(
              controller: cObs,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "Observações"),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                onPressed: () {
                  setState(() {
                    localSelecionado = cLoc.text;
                    observacoes = cObs.text;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text(
                  "SALVAR",
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
            child: Text(
              "Selecione o Nível",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _opcaoNivel("Várzea (Livre)", 35.0),
          _opcaoNivel("Intermediário (Médio)", 36.0),
          _opcaoNivel("Elite (Master)", 38.0),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _opcaoNivel(String nome, double precoBase) {
    return ListTile(
      title: Text(nome, style: const TextStyle(color: Colors.white)),
      trailing: Text(
        "R\$ ${precoBase.toStringAsFixed(2)}/h",
        style: TextStyle(color: primaryColor),
      ),
      onTap: () {
        setState(() {
          nivelGoleiro = nome;
          valorJogo = precoBase * (duracaoSelecionada / 60);
        });
        Navigator.pop(context);
      },
    );
  }

  void _modalRecargaRapida(double saldoAtual, double valorTotal) {
    double falta = valorTotal - saldoAtual;
    TextEditingController recargaController = TextEditingController(
      text: falta.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Saldo Insuficiente",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Faltam R\$ ${falta.toStringAsFixed(2)} para criar este jogo.",
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: recargaController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Valor para adicionar",
                labelStyle: const TextStyle(color: Colors.grey),
                prefixText: "R\$ ",
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            // Dentro de _modalRecargaRapida, no onPressed do ElevatedButton:
            onPressed: () async {
              double valor = double.tryParse(recargaController.text) ?? 0;
              if (valor <= 0) return;

              Navigator.pop(ctx); // Fecha o modal de entrada de valor
              setState(() => _processando = true);

              try {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final userRef = FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid);
                final extratoRef = userRef.collection('extrato').doc();

                WriteBatch batch = FirebaseFirestore.instance.batch();

                // Atualiza Saldo
                batch.update(userRef, {'saldo': saldoAtual + valor});

                // Registra no Financeiro (Extrato)
                batch.set(extratoRef, {
                  "id": extratoRef.id,
                  "idUsuario": uid,
                  "tipo": "entrada",
                  "valor": valor,
                  "saldoAnterior": saldoAtual,
                  "saldoAtual": saldoAtual + valor,
                  "descricao": "Recarga via Convocação",
                  "categoria": "recarga",
                  "data": FieldValue.serverTimestamp(),
                });

                await batch.commit();

                if (mounted) {
                  setState(() => _processando = false);

                  // CHAMA O VISUAL PREMIUM
                  _showSuccessVisual("Saldo Adicionado!", () {
                    validarEProcessar(); // Só avança depois que o visual some
                  });
                }
              } catch (e) {
                setState(() => _processando = false);
                _msgErro("Erro ao recarregar: $e");
              }
            },
            child: const Text(
              "RECARREGAR",
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirResumoFinal(double saldoAtual) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "CONFIRMAR CONVOCAÇÃO",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _itemResumo(
              Icons.calendar_today,
              "Data/Hora",
              "${dataSelecionada!.day}/${dataSelecionada!.month} às ${horarioSelecionado!.format(context)}",
            ),
            _itemResumo(Icons.place, "Local", localSelecionado),
            _itemResumo(Icons.timer, "Duração", "${(duracaoSelecionada / 60).toStringAsFixed(0)}h"),
            _itemResumo(Icons.bolt, "Nível", nivelGoleiro),
            const Divider(color: Colors.white12, height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total a pagar:",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                Text(
                  "R\$ ${valorJogo.toStringAsFixed(2)}",
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  salvarNoFirebase(saldoAtual);
                },
                child: const Text(
                  "CONFIRMAR E CRIAR JOGO",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

Future<void> salvarNoFirebase(double saldoAntes) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _processando = true);

    // --- ALTERAÇÃO AQUI: Criar o ponto de início e de fim ---
final DateTime dataHoraInicio = DateTime(
      dataSelecionada!.year,
      dataSelecionada!.month,
      dataSelecionada!.day,
      horarioSelecionado!.hour,
      horarioSelecionado!.minute,
    );

    // Calcula o fim com base na duração (60, 90, 120 min...)
    final DateTime dataHoraFim = dataHoraInicio.add(Duration(minutes: duracaoSelecionada));

      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference userRef = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid);

      DocumentReference jogoRef = widget.dados != null
          ? FirebaseFirestore.instance
                .collection("jogos")
                .doc(widget.dados!["id"])
          : FirebaseFirestore.instance.collection("jogos").doc();

      DocumentReference extratoRef = userRef.collection('extrato').doc();

      // 2. Lógica Financeira e Descrição do Extrato
      double valorAntigo = (widget.dados?["valor"] ?? 0.0).toDouble();

      // Se novo: saldo diminui pelo valor total (-valorJogo)
      // Se edição: saldo recebe a diferença (valor que já paguei - novo valor)
      double diferencaSaldo = widget.dados == null
          ? -valorJogo
          : valorAntigo - valorJogo;

      // Definição da descrição para o histórico financeiro
      String descricaoExtrato = "";
      if (widget.dados == null) {
        descricaoExtrato = "Convocação: $localSelecionado";
      } else {
        if (diferencaSaldo > 0) {
          descricaoExtrato = "Estorno (Edição): $localSelecionado";
        } else if (diferencaSaldo < 0) {
          descricaoExtrato = "Diferença (Edição): $localSelecionado";
        } else {
          descricaoExtrato = "Ajuste de detalhes: $localSelecionado";
        }
      }

      double saldoDepois = saldoAntes + diferencaSaldo;

      // 3. Atualiza o Saldo do Usuário
      batch.update(userRef, {"saldo": saldoDepois});

      // 4. Registra no Extrato (apenas se houve movimentação financeira)
      if (diferencaSaldo != 0) {
        batch.set(extratoRef, {
          "id": extratoRef.id,
          "idUsuario": uid,
          "idReferencia": jogoRef.id,
          "tipo": diferencaSaldo > 0 ? "entrada" : "saida",
          "valor": diferencaSaldo.abs(), // Sempre grava o valor positivo
          "saldoAnterior": saldoAntes,
          "saldoAtual": saldoDepois,
          "descricao": descricaoExtrato,
          "categoria": "jogo",
          "data": FieldValue.serverTimestamp(),
        });
      }

      // 5. Salva/Atualiza os Dados do Jogo
      batch.set(jogoRef, {
      "id": jogoRef.id,
      "local": localSelecionado,
      "dataHora": Timestamp.fromDate(dataHoraInicio), // Início
      "dataHoraFim": Timestamp.fromDate(dataHoraFim), // <--- NOVO CAMPO PARA A CLOUD FUNCTION
      "dataExibicao": "${dataSelecionada!.day.toString().padLeft(2, '0')}/${dataSelecionada!.month.toString().padLeft(2, '0')}",
      "horaExibicao": "${horarioSelecionado!.hour.toString().padLeft(2, '0')}:${horarioSelecionado!.minute.toString().padLeft(2, '0')}",
      "valor": valorJogo, 
      "status": widget.dados?["status"] ?? "aberto",
      "idContratante": uid,
      "observacoes": observacoes,
      "nivelGoleiro": nivelGoleiro,
      "duracao": duracaoSelecionada,
      "criadoEm": widget.dados?["criadoEm"] ?? FieldValue.serverTimestamp(),
      "editadoEm": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

      // Executa todas as operações de uma vez
      await batch.commit();

      // 6. Feedback Visual Premium
      if (mounted) {
        _showSuccessVisual(
          widget.dados != null ? "Atualizado!" : "Publicado!",
          () {
            if (widget.onFinalizado != null) {
              widget.onFinalizado!();
            } else {
              // Se não houver callback, volta para a tela anterior
              Navigator.pop(context);
            }
          },
        );
      }
    } catch (e) {
      if (mounted) setState(() => _processando = false);
      _msgErro("Erro ao salvar: $e");
    }
  }

  void _msgErro(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.redAccent),
    );
  }
} // Fecha a classe _TelaCriarJogoState
