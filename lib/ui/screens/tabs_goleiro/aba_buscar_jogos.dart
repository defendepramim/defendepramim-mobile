import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AbaBuscarJogos extends StatefulWidget {
  const AbaBuscarJogos({super.key});

  @override
  State<AbaBuscarJogos> createState() => _AbaBuscarJogosState();
}

class _AbaBuscarJogosState extends State<AbaBuscarJogos> {
  Timer? _timer;
  Duration _diferencaServidor = Duration.zero;
  final Color primaryColor = const Color(0xFF00E676);
  String? _jogoProcessando; 

  @override
  void initState() {
    super.initState();
    _inicializarDados();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- 🛰️ UTILITÁRIOS ---

  Future<void> _inicializarDados() async {
    await _sincronizarRelogio();
    if (mounted) {
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _sincronizarRelogio() async {
    try {
      final docRef = FirebaseFirestore.instance.collection('temp_time').doc();
      await docRef.set({'hora': FieldValue.serverTimestamp()});
      final snap = await docRef.get();
      await docRef.delete();
      if (mounted && snap.exists) {
        final DateTime horaServidor = (snap.get('hora') as Timestamp).toDate();
        setState(() {
          _diferencaServidor = horaServidor.difference(DateTime.now());
        });
      }
    } catch (_) {}
  }

  DateTime _obterHoraRealAgora() => DateTime.now().add(_diferencaServidor);

  String _formatarTempoRestante(DateTime dataJogo) {
    final agora = _obterHoraRealAgora();
    final diferenca = dataJogo.difference(agora);
    
    if (diferenca.isNegative) return "Iniciando...";
    if (diferenca.inDays > 0) return "Faltam ${diferenca.inDays} dias";
    if (diferenca.inHours > 0) return "Faltam ${diferenca.inHours}h ${diferenca.inMinutes % 60}m";
    return "Faltam ${diferenca.inMinutes} min!";
  }

  // --- 🛡️ PROCESSO DE ACEITE ---

  void _confirmarAceite(BuildContext context, String idJogo, Map<String, dynamic> jogo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirmar Presença?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text("Você confirma que irá comparecer ao ${jogo['local']}?\n\nLembre-se: desistências em menos de 4h geram multa.", 
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processarAceite(context, idJogo);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            child: const Text("CONFIRMAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processarAceite(BuildContext context, String idJogo) async {
    final String? uidGoleiro = FirebaseAuth.instance.currentUser?.uid;
    if (uidGoleiro == null) return;

    setState(() => _jogoProcessando = idJogo);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);
        DocumentSnapshot snapNovoJogo = await transaction.get(jogoRef);

        if (!snapNovoJogo.exists || snapNovoJogo.get('status') != 'aberto') {
          throw Exception("Putz! Outro goleiro foi mais rápido e pegou esta pelada.");
        }

        final dadosNovo = snapNovoJogo.data() as Map<String, dynamic>;
        final DateTime inicioNovo = (dadosNovo['dataHora'] as Timestamp).toDate();
        final int duracaoHoras = dadosNovo['duracao'] ?? 1;
        final DateTime fimNovo = inicioNovo.add(Duration(hours: duracaoHoras));

        if (inicioNovo.isBefore(_obterHoraRealAgora())) {
           throw Exception("O horário de início desta pelada já passou.");
        }

        final jogosAgendadosQuery = await FirebaseFirestore.instance
            .collection('jogos')
            .where('idGoleiro', isEqualTo: uidGoleiro)
            .where('status', isEqualTo: 'fechado')
            .get();

        for (var doc in jogosAgendadosQuery.docs) {
          final DateTime inicioExistente = (doc['dataHora'] as Timestamp).toDate();
          final int duracaoEx = doc['duracao'] ?? 1;
          final DateTime fimExistente = inicioExistente.add(Duration(hours: duracaoEx));

          if (inicioNovo.isBefore(fimExistente) && fimNovo.isAfter(inicioExistente)) {
            throw Exception("Conflito de agenda! Você já tem jogo às ${inicioExistente.hour}:${inicioExistente.minute.toString().padLeft(2, '0')}.");
          }
        }

        transaction.update(jogoRef, {
          'status': 'fechado',
          'idGoleiro': uidGoleiro,
          'aceitoEm': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("🧤 Pelada confirmada com sucesso!")));
      }
} catch (e) {
      if (context.mounted) {
        String mensagem = e.toString().replaceAll("Exception: ", "");
        
        // Se a mensagem for a de "Outro goleiro", podemos dar um destaque especial
        if (mensagem.contains("Outro goleiro")) {
          _showAvisoVagaPreenchida(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent, 
              content: Text("❌ $mensagem"),
              behavior: SnackBarBehavior.floating,
            )
          );
        }
      }
    } finally {
      if (mounted) setState(() => _jogoProcessando = null);
    }
  }

  // --- 💡 UI EXTRA: AVISO DE VAGA PREENCHIDA ---
  void _showAvisoVagaPreenchida(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Vaga Preenchida! 🧤", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Putz! Outro goleiro foi mais rápido e confirmou a presença primeiro.\n\nNão desanime, logo aparece outra pelada!",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK, ENTENDI", style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? uidGoleiro = FirebaseAuth.instance.currentUser?.uid;
    final agoraReal = _obterHoraRealAgora();

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            backgroundColor: Colors.black,
            floating: true,
            title: Text("Jogos Disponíveis", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('jogos')
                .where('status', isEqualTo: 'aberto')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const SliverToBoxAdapter(child: Center(child: Text("Erro ao carregar")));
              if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))));

              final documentosFull = snapshot.data?.docs ?? [];
              
              final documentos = documentosFull.where((doc) {
                final dados = doc.data() as Map<String, dynamic>;
                final List desistentes = dados['desistentes'] ?? [];
                if (desistentes.contains(uidGoleiro)) return false;
                final DateTime dtAbsoluta = (dados['dataHora'] as Timestamp).toDate();
                if (dtAbsoluta.isBefore(agoraReal)) return false;
                return true;
              }).toList();

              documentos.sort((a, b) {
                 final dtA = (a.data() as Map<String, dynamic>)['dataHora'] as Timestamp;
                 final dtB = (b.data() as Map<String, dynamic>)['dataHora'] as Timestamp;
                 return dtA.compareTo(dtB);
              });

              if (documentos.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text("Nenhuma pelada disponível no momento. ⚽", style: TextStyle(color: Colors.grey, fontSize: 16)))),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = documentos[index];
                      final jogo = doc.data() as Map<String, dynamic>;
                      return _buildCardBusca(context, jogo, doc.id);
                    },
                    childCount: documentos.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCardBusca(BuildContext context, Map<String, dynamic> jogo, String id) {
    final DateTime dtAbsoluta = (jogo['dataHora'] as Timestamp).toDate();
    final bool isNear = dtAbsoluta.difference(_obterHoraRealAgora()).inHours < 2;
    final bool isProcessing = _jogoProcessando == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isNear ? Colors.orange.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // No _buildCardBusca, troque o container do ícone por:
Container(
  height: 100, width: double.infinity,
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Colors.white.withOpacity(0.05), Colors.transparent],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    ),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
  ),
  child: Icon(
    jogo['categoria'] == 'futsal' ? Icons.sports_soccer : Icons.stadium_outlined, 
    color: Colors.white.withOpacity(0.05), 
    size: 60
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
                    Expanded(child: Text(jogo['local'] ?? 'Arena', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
                    Text("R\$ ${jogo['valor']}", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _infoBadge(Icons.access_time, _formatarTempoRestante(dtAbsoluta), isNear ? Colors.orange : primaryColor),
                    const SizedBox(width: 12),
                    _infoBadge(Icons.calendar_month, "${dtAbsoluta.day.toString().padLeft(2,'0')}/${dtAbsoluta.month.toString().padLeft(2,'0')} às ${dtAbsoluta.hour.toString().padLeft(2,'0')}:${dtAbsoluta.minute.toString().padLeft(2, '0')}", Colors.grey),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _confirmarAceite(context, id, jogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isProcessing ? Colors.grey[800] : primaryColor, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                      elevation: 0
                    ),
                    child: isProcessing
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("ACEITAR JOGO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Row(children: [Icon(icon, color: color.withOpacity(0.7), size: 14), const SizedBox(width: 4), Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))]);
  }
}