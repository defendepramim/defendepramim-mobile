import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'package:defendepramim/services/notificacao_service.dart';

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

  // 🌍 GEOLOCALIZAÇÃO E PERFIL
  Position? _posicaoGoleiro;
  double _raioBuscaKm = 20.0;
  bool _buscandoGPS = true;
  bool _erroGps = false; 

  // 🛡️ REGRAS DINÂMICAS E RANK DO GOLEIRO
  int _reqExperientePartidas = 5;
  double _reqExperienteNota = 4.2;
  int _reqElitePartidas = 15;
  double _reqEliteNota = 4.5;
  
  int _rankGoleiroCalculado = 0;
  bool _carregandoPerfil = true;

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

  Future<void> _inicializarDados() async {
    await _carregarConfiguracoesEPerfil();
    await _sincronizarRelogio();
    await _pegarLocalizacaoGoleiro(); 
    
    if (mounted) {
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _carregarConfiguracoesEPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final configDoc = await FirebaseFirestore.instance.collection('configuracoes').doc('global').get();
      if (configDoc.exists) {
        final c = configDoc.data()!;
        _reqExperientePartidas = (c['reqExperientePartidas'] ?? 5).toInt();
        _reqExperienteNota = (c['reqExperienteNota'] ?? 4.2).toDouble();
        _reqElitePartidas = (c['reqElitePartidas'] ?? 15).toInt();
        _reqEliteNota = (c['reqEliteNota'] ?? 4.5).toDouble();
      }

      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        
        final int totalPartidas = (d['atuadas'] as num?)?.toInt() ?? (d['jogosRealizados'] as num?)?.toInt() ?? 0;
        
        final double somaAvaliacoes = (d['somaAvaliacoes'] as num?)?.toDouble() ?? 0.0;
        final int totalAvaliacoes = (d['totalAvaliacoes'] as num?)?.toInt() ?? 0;
        final double notaMedia = totalAvaliacoes > 0 ? (somaAvaliacoes / totalAvaliacoes) : 0.0;
        
        if (totalPartidas >= _reqElitePartidas && notaMedia >= _reqEliteNota) {
          _rankGoleiroCalculado = 2; // Elite
        } else if (totalPartidas >= _reqExperientePartidas && notaMedia >= _reqExperienteNota) {
          _rankGoleiroCalculado = 1; // Experiente
        } else {
          _rankGoleiroCalculado = 0; // Livre
        }

        setState(() {
          _carregandoPerfil = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar perfil e configs: $e");
      if (mounted) setState(() => _carregandoPerfil = false);
    }
  }

bool _isGoleiroElegivel(String nivelExigidoJogo) {
    int rankExigido = 0;
    final nJ = nivelExigidoJogo.toLowerCase();
    
    if (nJ.contains('elite') || nJ.contains('pared')) {
      rankExigido = 2;
    } else if (nJ.contains('exp') || nJ.contains('inter') || nJ.contains('médio') || nJ.contains('medio')) {
      rankExigido = 1;
    }
    return _rankGoleiroCalculado >= rankExigido;
  }

Future<void> _pegarLocalizacaoGoleiro() async {
    try {
      bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
      if (!servicoAtivo) throw Exception("GPS Desativado");

      LocationPermission permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
        if (permissao == LocationPermission.denied || permissao == LocationPermission.deniedForever) {
           throw Exception("Permissão negada");
        }
      }

      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _posicaoGoleiro = pos;
          _buscandoGPS = false;
          _erroGps = false; 
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _buscandoGPS = false;
          _erroGps = true; 
        });
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
    if (diferenca.inDays > 0) return "Faltam ${diferenca.inDays}d";
    if (diferenca.inHours > 0) return "Faltam ${diferenca.inHours}h ${diferenca.inMinutes % 60}m";
    return "Faltam ${diferenca.inMinutes} min!";
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

  void _confirmarAceite(BuildContext context, String idJogo, Map<String, dynamic> jogo) {
    // 🟢 TRAVA DE INTERFACE: Impede duplo clique no botão Aceitar
    if (_jogoProcessando != null) return; 

    final screenContext = context; 
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirmar Presença?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
            children: [
              const TextSpan(text: "Você confirma sua presença no jogo em "),
              TextSpan(
                text: "${jogo['local']}?\n\n", 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))
              ),
              const TextSpan(text: "⚽ Contamos com você no gol! "),
              const TextSpan(
                text: "Lembre-se: cancelamentos com menos de 4h de antecedência geram uma taxa de R\$ 10, descontada do seu próximo jogo.",
                style: TextStyle(color: Colors.white54, fontSize: 13),
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
      
      final String nivelExigido = (dadosNovo['nivelGoleiro'] ?? dadosNovo['nivel'] ?? 'Livre').toString();
      if (!_isGoleiroElegivel(nivelExigido)) {
        throw "Você não atende aos requisitos de partidas ou nota para este nível de partida.";
      }

      final String idContratante = dadosNovo['idContratante'] ?? ''; 
      
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

      String nomeGoleiroParaAviso = "Goleiro"; 
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference userRef = FirebaseFirestore.instance.collection('usuarios').doc(uidGoleiro);
        DocumentSnapshot userSnap = await transaction.get(userRef);
        
        final dadosGoleiro = userSnap.data() as Map<String, dynamic>?;
        nomeGoleiroParaAviso = dadosGoleiro?['nome'] ?? "Goleiro";

        DocumentReference jogoRef = FirebaseFirestore.instance.collection('jogos').doc(idJogo);
        
        // 🟢 PROTEÇÃO DE TRANSAÇÃO: Verifica se o jogo ainda está aberto ANTES de sobrescrever
        DocumentSnapshot jogoSnap = await transaction.get(jogoRef);
        if (jogoSnap.get('status') != 'aberto') {
          throw Exception("Ops! Outro goleiro foi mais rápido e já aceitou essa partida.");
        }

        transaction.update(jogoRef, {
          'status': 'fechado',
          'idGoleiro': uidGoleiro,
          'nomeGoleiro': nomeGoleiroParaAviso, 
          'aceitoEm': FieldValue.serverTimestamp(),
        });
      });

      if (idContratante.isNotEmpty) {
        final String diaMes = "${inicioNovo.day.toString().padLeft(2, '0')}/${inicioNovo.month.toString().padLeft(2, '0')}";
        final String horaStr = "${inicioNovo.hour.toString().padLeft(2, '0')}:${inicioNovo.minute.toString().padLeft(2, '0')}";

        await NotificacaoService().enviarNotificacao(
          idUsuarioDestino: idContratante,
          titulo: "Goleiro Confirmado! 🧤",
          mensagem: "O(a) $nomeGoleiroParaAviso aceitou a convocação em ${localNovo.split('(')[0].trim()} dia $diaMes às $horaStr.",
          tipo: 'aceitou_jogo',
        );
      }

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
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(13)),
        ),
        title: Row(
          children: [
            Icon(icone, color: corDestaque, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          ],
        ),
        content: Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: corDestaque.withAlpha(26),
                foregroundColor: corDestaque,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('jogos').where('status', isEqualTo: 'aberto').snapshots(),
        builder: (context, snapshot) {
          
          final documentosFiltrados = <DocumentSnapshot>[];
          final distanciasMap = <String, double>{};

          if (snapshot.hasData && !_buscandoGPS && !_carregandoPerfil) {
            for (var doc in snapshot.data!.docs) {
              final dados = doc.data() as Map<String, dynamic>;

              final String nivelExigido = (dados['nivelGoleiro'] ?? dados['nivel'] ?? 'Livre').toString();
              if (!_isGoleiroElegivel(nivelExigido)) {
                continue; 
              }

              final List desistentes = dados['desistentes'] ?? [];
              if (desistentes.contains(uidGoleiro)) continue;
              
              final DateTime dtAbsoluta = (dados['dataHora'] as Timestamp).toDate();
              if (dtAbsoluta.isBefore(agoraReal)) continue;

              double distanciaCalculada = 999.0; 
              if (_posicaoGoleiro != null) {
                double? latDoc;
                double? lngDoc;

                if (dados['latitude'] != null) {
                  latDoc = (dados['latitude'] as num).toDouble();
                } else if (dados['lat'] != null) latDoc = (dados['lat'] as num).toDouble();
                else if (dados['localizacao'] is GeoPoint) latDoc = (dados['localizacao'] as GeoPoint).latitude;

                if (dados['longitude'] != null) {
                  lngDoc = (dados['longitude'] as num).toDouble();
                } else if (dados['lng'] != null) lngDoc = (dados['lng'] as num).toDouble();
                else if (dados['localizacao'] is GeoPoint) lngDoc = (dados['localizacao'] as GeoPoint).longitude;

                if (latDoc != null && lngDoc != null) {
                  distanciaCalculada = Geolocator.distanceBetween(
                    _posicaoGoleiro!.latitude, _posicaoGoleiro!.longitude,
                    latDoc, lngDoc
                  ) / 1000; 
                }
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
                title: const Text("Jogos Disponíveis", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(60), 
                  child: _buildFiltroRaio(qtdJogosFiltrados), 
                ),
              ),
              
              if (_buscandoGPS || _carregandoPerfil || !snapshot.hasData)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
                  ),
                )
else if (snapshot.hasError)
                const SliverToBoxAdapter(child: Center(child: Text("Erro ao carregar", style: TextStyle(color: Colors.white))))
              
              else if (_erroGps)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 80, left: 30, right: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 60),
                        const SizedBox(height: 16),
                        const Text("GPS Necessário", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text("Você precisa ativar o GPS do celular e permitir o acesso para buscar jogos na sua região.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                           style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.black),
                           onPressed: () {
                             setState(() { _buscandoGPS = true; _erroGps = false; });
                             _pegarLocalizacaoGoleiro();
                           },
                           child: const Text("TENTAR NOVAMENTE", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                )
              else if (documentosFiltrados.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: Text("Nenhum jogo no seu raio de busca. ⚽", style: TextStyle(color: Colors.grey, fontSize: 15))),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Widget _buildFiltroRaio(int qtdJogos) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), 
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: Colors.grey, size: 18),
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "$qtdJogos", 
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)
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

    final String localCompleto = jogo['local'] ?? 'Endereço não informado';
    final String obs = jogo['observacoes']?.toString() ?? ''; 
    final String tipoQuadra = jogo['tipoQuadra'] ?? 'Society';

    double? lat;
    double? lng;

    if (jogo['latitude'] != null) lat = (jogo['latitude'] as num).toDouble();
    else if (jogo['lat'] != null) lat = (jogo['lat'] as num).toDouble();
    else if (jogo['localizacao'] is GeoPoint) lat = (jogo['localizacao'] as GeoPoint).latitude;

    if (jogo['longitude'] != null) lng = (jogo['longitude'] as num).toDouble();
    else if (jogo['lng'] != null) lng = (jogo['lng'] as num).toDouble();
    else if (jogo['localizacao'] is GeoPoint) lng = (jogo['localizacao'] as GeoPoint).longitude;

    DateTime dataAlvoReal;
    try {
      final partesData = dataExibicao.split('/');
      final partesHora = horaExibicao.split(':');
      dataAlvoReal = DateTime(dtAbsoluta.year, int.parse(partesData[1]), int.parse(partesData[0]), int.parse(partesHora[0]), int.parse(partesHora[1]));
    } catch (e) {
      dataAlvoReal = dtAbsoluta; 
    }

    final bool isNear = dataAlvoReal.difference(_obterHoraRealAgora()).inHours < 2;
    
    final List<String> partesLocal = localCompleto.split('(');
    final String nomeQuadra = partesLocal[0].trim();
    final String enderecoRua = partesLocal.length > 1 ? partesLocal[1].replaceAll(')', '').trim() : "Endereço no mapa";

    final double valorRaw = (jogo['valorGoleiro'] ?? jogo['valor'] ?? 0.0).toDouble();
    final String valorFormatado = valorRaw.toStringAsFixed(2).replaceAll('.', ',');

    final String nivelRaw = (jogo['nivelGoleiro'] ?? jogo['nivel'] ?? 'Livre').toString().toLowerCase();
    String textoNivel = "Livre";
    Color corNivel = Colors.white54;
    IconData iconeNivel = Icons.shield_outlined;

    if (nivelRaw.contains('elite') || nivelRaw.contains('pared')) {
      textoNivel = "Elite";
      corNivel = Colors.amber;
      iconeNivel = Icons.emoji_events;
    } else if (nivelRaw.contains('exp') || nivelRaw.contains('inter') || nivelRaw.contains('médio') || nivelRaw.contains('medio')) {
      textoNivel = "Experiente";
      corNivel = Colors.blueAccent;
      iconeNivel = Icons.military_tech;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isNear ? Colors.orange.withAlpha(120) : Colors.white.withAlpha(15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 8, offset: const Offset(0, 4)),
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: primaryColor.withAlpha(12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("VOCÊ GANHA", style: TextStyle(color: primaryColor.withAlpha(200), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    const SizedBox(height: 1),
                    Text("R\$ $valorFormatado", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 22)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: corNivel.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: corNivel.withAlpha(50)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconeNivel, color: corNivel, size: 13),
                      const SizedBox(width: 4),
                      Text(textoNivel, style: TextStyle(color: corNivel, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(_obterIconeQuadra(tipoQuadra), color: Colors.grey, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nomeQuadra, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(enderecoRua, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          
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
                                    const Icon(Icons.info_outline, color: Colors.white38, size: 13),
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
                    Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: IconButton(
                        onPressed: () => _abrirNoMapaNativo(lat, lng, nomeQuadra, enderecoRua),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(8),
                            border: Border.all(color: Colors.white.withAlpha(15)),
                          ),
                          child: const Icon(Icons.map_outlined, color: Colors.blueAccent, size: 16),
                        ),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        tooltip: "Abrir Rota",
                      ),
                    )
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _infoBadge(Icons.calendar_month, "$dataExibicao às $horaExibicao", Colors.white70),
                    _infoBadge(_obterIconeQuadra(tipoQuadra), tipoQuadra, Colors.white70),
                    _infoBadge(Icons.access_time, _formatarTempoRestante(dataAlvoReal), isNear ? Colors.orange : Colors.white70),
                    if (_posicaoGoleiro != null) 
                      _infoBadge(Icons.route, "${distanciaEmKm.toStringAsFixed(1)} km", Colors.blueAccent),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _confirmarAceite(context, id, jogo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isProcessing ? Colors.white12 : primaryColor,
                      foregroundColor: isProcessing ? Colors.white54 : Colors.black, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: (isNear && !isProcessing) ? 4 : 0, 
                      shadowColor: primaryColor.withAlpha(100),
                    ),
                    child: isProcessing
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Text("ACEITAR CONVOCAÇÃO", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirNoMapaNativo(double? lat, double? lng, String nomeArena, String endereco) async {
    Uri url;

    if (lat != null && lng != null) {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      final String termoBusca = Uri.encodeComponent("$nomeArena, $endereco");
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$termoBusca');
    }
    
    try {
      bool disparado = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!disparado) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint("Erro ao abrir mapa: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível abrir o aplicativo de mapas."), backgroundColor: Colors.orangeAccent),
        );
      }
    }
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withAlpha(40))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}