import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:url_launcher/url_launcher.dart'; 

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

  // 🌍 MÁGICA DA GEOLOCALIZAÇÃO
  Position? _posicaoGoleiro;
  double _raioBuscaKm = 20.0; // Distância padrão
  bool _buscandoGPS = true;

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
    await _pegarLocalizacaoGoleiro(); 
    
    if (mounted) {
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _pegarLocalizacaoGoleiro() async {
    try {
      bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
      if (!servicoAtivo) throw Exception("GPS Desativado");

      LocationPermission permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
        if (permissao == LocationPermission.denied) throw Exception("Permissão negada");
      }

      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _posicaoGoleiro = pos;
          _buscandoGPS = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _buscandoGPS = false);
      }
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

  void _confirmarAceite(BuildContext context, String idJogo, Map<String, dynamic> jogo) {
    final screenContext = context; 
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirmar Presença?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
            children: [
              const TextSpan(text: "Você confirma sua presença no jogo em "),
              TextSpan(
                text: "${jogo['local']}?\n\n", 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))
              ),
              const TextSpan(text: "⚽ Contamos com você no gol! "),
              const TextSpan(
                text: "Lembre-se: cancelamentos com menos de 4h de antecedência geram uma taxa de R\$ 10, descontada do seu próximo jogo.",
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext), 
            child: const Text("CANCELAR", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); 
              _processarAceite(screenContext, idJogo); 
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

    if (!mounted) return;
    setState(() => _jogoProcessando = idJogo);

    try {
      final snapNovo = await FirebaseFirestore.instance.collection('jogos').doc(idJogo).get();
      final dadosNovo = snapNovo.data() as Map<String, dynamic>;
      final DateTime inicioNovo = (dadosNovo['dataHora'] as Timestamp).toDate();
      final int duracaoMinNovo = (dadosNovo['duracao'] ?? 60).toInt();
      final DateTime fimNovo = inicioNovo.add(Duration(minutes: duracaoMinNovo));
      final String localNovo = (dadosNovo['local'] ?? '').toString().trim();

      final DateTime inicioDoDia = DateTime(inicioNovo.year, inicioNovo.month, inicioNovo.day, 0, 0, 0);
      final DateTime fimDoDia = DateTime(inicioNovo.year, inicioNovo.month, inicioNovo.day, 23, 59, 59);

      final conflitosQuery = await FirebaseFirestore.instance
          .collection('jogos')
          .where('idGoleiro', isEqualTo: uidGoleiro)
          .where('status', whereIn: ['fechado', 'finalizado'])
          .where('dataHora', isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDoDia))
          .where('dataHora', isLessThanOrEqualTo: Timestamp.fromDate(fimDoDia))
          .get();

      for (var doc in conflitosQuery.docs) {
        if (doc.id == idJogo) continue;
        final dadosEx = doc.data();
        final DateTime inicioEx = (dadosEx['dataHora'] as Timestamp).toDate();
        final int duracaoEx = (dadosEx['duracao'] ?? 60).toInt();
        final String localEx = (dadosEx['local'] ?? '').toString().trim();

        DateTime fimExCalculado = inicioEx.add(Duration(minutes: duracaoEx));
        bool precisaDeslocamento = localEx.toLowerCase() != localNovo.toLowerCase();

        if (precisaDeslocamento) fimExCalculado = fimExCalculado.add(const Duration(minutes: 30));

        if (inicioNovo.isBefore(fimExCalculado) && fimNovo.isAfter(inicioEx)) {
          throw precisaDeslocamento
              ? "CONFLITO: Você já tem jogo em '$localEx'. Precisa de 30min para deslocamento."
              : "CONFLITO: Você já tem um jogo neste horário em '$localEx'.";
        }
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference userRef = FirebaseFirestore.instance.collection('usuarios').doc(uidGoleiro);
        DocumentSnapshot userSnap = await transaction.get(userRef);
        
        final dadosGoleiro = userSnap.data() as Map<String, dynamic>?;
        String nomeGoleiroLogado = dadosGoleiro?['nome'] ?? "Goleiro";

        DocumentReference jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);
        
        transaction.update(jogoRef, {
          'status': 'fechado',
          'idGoleiro': uidGoleiro,
          'nomeGoleiro': nomeGoleiroLogado, 
          'aceitoEm': FieldValue.serverTimestamp(),
        });
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("🧤 Jogo aceito!")),
        );
      }

    } catch (e) {
      debugPrint("❌ ERRO NO CATCH: $e");
      
      if (context.mounted) {
        String msgFinal = e.toString().replaceAll("Exception: ", "");
        
        _showAlertaCustom(
          context,
          titulo: msgFinal.contains("CONFLITO") ? "Agenda Cheia" : "Ops!",
          mensagem: msgFinal,
          icone: msgFinal.contains("CONFLITO") ? Icons.event_busy : Icons.error_outline,
          corDestaque: msgFinal.contains("CONFLITO") ? Colors.orangeAccent : primaryColor,
        );
      }
    } finally {
      if (mounted) setState(() => _jogoProcessando = null);
    }
  }

  void _showAlertaCustom(
    BuildContext context, {
    required String titulo,
    required String mensagem,
    IconData icone = Icons.warning_amber_rounded,
    Color corDestaque = const Color(0xFF00E676),
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          // withOpacity(0.05) -> withAlpha(13)
          side: BorderSide(color: Colors.white.withAlpha(13)),
        ),
        title: Row(
          children: [
            Icon(icone, color: corDestaque, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                // withOpacity(0.1) -> withAlpha(26)
                backgroundColor: corDestaque.withAlpha(26),
                foregroundColor: corDestaque,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("ENTENDI", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
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
      // 🟢 O STREAMBUILDER AGORA ENVOLVE TUDO PARA CONSEGUIR CONTAR OS JOGOS ANTES DE DESENHAR O CABEÇALHO
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('jogos').where('status', isEqualTo: 'aberto').snapshots(),
        builder: (context, snapshot) {
          
          final documentosFiltrados = <DocumentSnapshot>[];
          final distanciasMap = <String, double>{};

          // Só processa a lista se tiver carregado e não estiver buscando GPS
          if (snapshot.hasData && !_buscandoGPS) {
            for (var doc in snapshot.data!.docs) {
              final dados = doc.data() as Map<String, dynamic>;
              final List desistentes = dados['desistentes'] ?? [];
              if (desistentes.contains(uidGoleiro)) continue;
              
              final DateTime dtAbsoluta = (dados['dataHora'] as Timestamp).toDate();
              if (dtAbsoluta.isBefore(agoraReal)) continue;

              double distanciaCalculada = 999.0; 
              if (_posicaoGoleiro != null && dados['localizacao'] is GeoPoint) {
                final GeoPoint localJogo = dados['localizacao'];
                distanciaCalculada = Geolocator.distanceBetween(
                  _posicaoGoleiro!.latitude, _posicaoGoleiro!.longitude,
                  localJogo.latitude, localJogo.longitude
                ) / 1000; 
              }

              if (distanciaCalculada <= _raioBuscaKm) {
                documentosFiltrados.add(doc);
                distanciasMap[doc.id] = distanciaCalculada;
              }
            }

            documentosFiltrados.sort((a, b) {
              final dtA = (a.data() as Map<String, dynamic>)['dataHora'] as Timestamp;
              final dtB = (b.data() as Map<String, dynamic>)['dataHora'] as Timestamp;
              return dtA.compareTo(dtB);
            });
          }

          final int qtdJogosFiltrados = documentosFiltrados.length;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.black,
                floating: true,
                pinned: true, 
                title: const Text("Jogos Disponíveis", style: TextStyle(fontWeight: FontWeight.bold)),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(70), 
                  // 🟢 PASSANDO O NÚMERO DE JOGOS PRO CABEÇALHO
                  child: _buildFiltroRaio(qtdJogosFiltrados), 
                ),
              ),
              
              if (_buscandoGPS || !snapshot.hasData)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                  ),
                )
              else if (snapshot.hasError)
                const SliverToBoxAdapter(child: Center(child: Text("Erro ao carregar", style: TextStyle(color: Colors.white))))
              else if (documentosFiltrados.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: Text("Nenhum jogo no seu raio de busca. ⚽", style: TextStyle(color: Colors.grey, fontSize: 16))),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = documentosFiltrados[index];
                        final dados = doc.data() as Map<String, dynamic>;
                        final dist = distanciasMap[doc.id] ?? 0.0;
                        return _buildCardBusca(context, dados, doc.id, dist);
                      },
                      childCount: documentosFiltrados.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 🎚️ WIDGET DO SLIDER COM CONTADOR DE JOGOS
  Widget _buildFiltroRaio(int qtdJogos) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), 
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: Colors.grey, size: 20),
          const SizedBox(width: 6), 
          
          Flexible(
            flex: 2, 
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    "Raio: ${_raioBuscaKm.toInt()}km", 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 8),
                  // 🟢 O NOVO BADGE DE CONTAGEM EM TEMPO REAL
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$qtdJogos", 
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            flex: 5, 
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: primaryColor,
                inactiveTrackColor: Colors.white12,
                thumbColor: primaryColor,
                // withOpacity(0.2) -> withAlpha(51)
                overlayColor: primaryColor.withAlpha(51),
                trackHeight: 2.0,
              ),
              child: Slider(
                value: _raioBuscaKm,
                min: 5.0,
                max: 100.0,
                divisions: 19, 
                onChanged: (val) => setState(() => _raioBuscaKm = val),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBusca(BuildContext context, Map<String, dynamic> jogo, String id, double distanciaEmKm) {
    final bool isProcessing = _jogoProcessando == id;

    final DateTime dtAbsoluta = (jogo['dataHora'] as Timestamp).toDate();
    final String dataExibicao = jogo['dataExibicao'] ?? "${dtAbsoluta.day.toString().padLeft(2, '0')}/${dtAbsoluta.month.toString().padLeft(2, '0')}";
    final String horaExibicao = jogo['horaExibicao'] ?? "${dtAbsoluta.hour.toString().padLeft(2, '0')}:${dtAbsoluta.minute.toString().padLeft(2, '0')}";

    DateTime dataAlvoReal;
    try {
      final partesData = dataExibicao.split('/');
      final partesHora = horaExibicao.split(':');
      dataAlvoReal = DateTime(dtAbsoluta.year, int.parse(partesData[1]), int.parse(partesData[0]), int.parse(partesHora[0]), int.parse(partesHora[1]));
    } catch (e) {
      dataAlvoReal = dtAbsoluta; 
    }

    final bool isNear = dataAlvoReal.difference(_obterHoraRealAgora()).inHours < 2;
    
    final String localCompleto = jogo['local'] ?? 'Endereço não informado';
    final List<String> partesLocal = localCompleto.split('(');
    final String nomeQuadra = partesLocal[0].trim();
    final String enderecoRua = partesLocal.length > 1 ? partesLocal[1].replaceAll(')', '').trim() : "Endereço no mapa";

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        // withOpacity(0.4) -> withAlpha(102) | withOpacity(0.05) -> withAlpha(13)
        border: Border.all(color: isNear ? Colors.orange.withAlpha(102) : Colors.white.withAlpha(13)),
        boxShadow: [
          // withOpacity(0.3) -> withAlpha(77)
          BoxShadow(color: Colors.black.withAlpha(77), blurRadius: 10, offset: const Offset(0, 5)),
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 15),
            decoration: BoxDecoration(
              // withOpacity(0.05) -> withAlpha(13)
              color: primaryColor.withAlpha(13),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // withOpacity(0.8) -> withAlpha(204)
                    Text("VOCÊ GANHA", style: TextStyle(color: primaryColor.withAlpha(204), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text("R\$ ${jogo['valorGoleiro'] ?? jogo['valor']}", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 28)),
                  ],
                ),
                Icon(jogo['categoria'] == 'futsal' ? Icons.sports_soccer : Icons.stadium_outlined, color: Colors.white10, size: 40),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.location_on, color: Colors.grey, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nomeQuadra, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(enderecoRua, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (jogo['latitude'] != null && jogo['longitude'] != null)
                      IconButton(
                        onPressed: () => _abrirNoMapaNativo(jogo['latitude'], jogo['longitude']),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          // withOpacity(0.1) -> withAlpha(26)
                          decoration: BoxDecoration(color: Colors.blueAccent.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.map_rounded, color: Colors.blueAccent, size: 20),
                        ),
                        tooltip: "Abrir Rota",
                      )
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    _infoBadge(Icons.calendar_month, "$dataExibicao às $horaExibicao", Colors.white70),
                    _infoBadge(Icons.access_time, _formatarTempoRestante(dataAlvoReal), isNear ? Colors.orange : Colors.white70),
                    if (_posicaoGoleiro != null) 
                      _infoBadge(Icons.route, "${distanciaEmKm.toStringAsFixed(1)} km", Colors.blueAccent),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _confirmarAceite(context, id, jogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isProcessing ? Colors.grey[800] : primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: isNear ? 8 : 2,
                      // withOpacity(0.5) -> withAlpha(128)
                      shadowColor: primaryColor.withAlpha(128),
                    ),
                    child: isProcessing
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text("ACEITAR CONVOCAÇÃO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirNoMapaNativo(double lat, double lng) async {
    final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication); 
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o mapa.")));
        }
      }
    } catch (e) {
      debugPrint("Erro ao abrir mapa: $e");
    }
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // withOpacity(0.1) -> withAlpha(26) | withOpacity(0.2) -> withAlpha(51)
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(51))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}