import 'dart:convert';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defendepramim/core/chaves.dart';
import 'dart:ui' as ui;
import 'package:defendepramim/icons/mapa_icons_icons.dart';

class MapaSeletorPage extends StatefulWidget {
  const MapaSeletorPage({super.key});

  @override
  State<MapaSeletorPage> createState() => _MapaSeletorPageState();
}

class _MapaSeletorPageState extends State<MapaSeletorPage> {
  GoogleMapController? _mapController;

  LatLng _posicaoAtual = const LatLng(-30.0346, -51.2177);
  bool _veioDaBusca = false;
  Set<Marker> _pinosQuadras = {};

  /// Metadados das quadras parceiras (nome, endereço, lat, lng)
  final Map<String, Map<String, dynamic>> _quadrasMeta = {};

  /// Ícone gota partilhado (sem texto no bitmap → leve)
  BitmapDescriptor? _iconeQuadraParceira;

  /// Raio para considerar "mesma zona" (metros)
  static const double _raioVizinhaMetros = 100;

  // ---- Notifiers: atualizam UI sem rebuild do GoogleMap ----
  final ValueNotifier<List<dynamic>> _previsoesVN = ValueNotifier(const []);
  final ValueNotifier<bool> _temTextoBuscaVN = ValueNotifier(false);
  final ValueNotifier<bool> _movendoVN = ValueNotifier(false);
  final ValueNotifier<bool> _carregandoGpsVN = ValueNotifier(true);
  final ValueNotifier<String> _ruaVN = ValueNotifier('Buscando endereço...');
  final ValueNotifier<String> _nomeLocalVN = ValueNotifier('');
  /// Chip flutuante quando toca num pin parceiro
  final ValueNotifier<String?> _chipQuadraVN = ValueNotifier(null);

  final TextEditingController _cBusca = TextEditingController();
  String _sessionToken = const Uuid().v4();

  final String _googleApiKey = ChavesSecretas.googleApiKey;
  final String _mapStyle =
      '''[{"elementType": "geometry", "stylers": [{"color": "#212121"}]},{"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},{"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},{"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]}]''';

  Timer? _debounceTimer;
  Timer? _searchDebounce;
  int _searchSeq = 0;
  bool _iconeCarregado = false;

  // Getters legados usados noutros métodos
  String get _ruaEletro => _ruaVN.value;
  String get _nomeLocalEletro => _nomeLocalVN.value;
  bool get _carregandoLocalizacao => _carregandoGpsVN.value;
  bool get _movendoMapa => _movendoVN.value;

  @override
  void initState() {
    super.initState();
    _pegarLocalizacaoAtual();
  }

  @override
  void dispose() {
    _cBusca.dispose();
    _debounceTimer?.cancel();
    _searchDebounce?.cancel();
    _previsoesVN.dispose();
    _temTextoBuscaVN.dispose();
    _movendoVN.dispose();
    _carregandoGpsVN.dispose();
    _ruaVN.dispose();
    _nomeLocalVN.dispose();
    _chipQuadraVN.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iconeCarregado) {
      _carregarQuadrasParceiras();
      _iconeCarregado = true;
    }
  }

  /// Pin B — badge flutuante (estilo Uber/Airbnb):
  /// círculo escuro + anel verde + ícone campo + pontinha em baixo.
  Future<BitmapDescriptor> _gerarIconeQuadraParceira() async {
    if (_iconeQuadraParceira != null) return _iconeQuadraParceira!;

    try {
      // Canvas compacto; âncora na ponta (0.5, 1.0)
      const double w = 56;
      const double h = 66;
      const double cx = w / 2;
      const double r = 18; // raio do badge
      const double cy = 20; // centro do círculo (deixar espaço para sombra/ponta)
      const double tipY = h - 2;
      const double tipHalf = 7;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // --- Sombra do conjunto ---
      final sombra = Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(const Offset(cx + 0.5, cy + 1.5), r, sombra);

      // --- Ponta pequena (triângulo) sob o círculo ---
      final ponta = Path()
        ..moveTo(cx - tipHalf, cy + r * 0.55)
        ..lineTo(cx, tipY)
        ..lineTo(cx + tipHalf, cy + r * 0.55)
        ..close();
      canvas.drawPath(ponta, Paint()..color = const Color(0xFF00E676));

      // --- Disco escuro (miolo) ---
      canvas.drawCircle(
        const Offset(cx, cy),
        r,
        Paint()..color = const Color(0xFF141414),
      );

      // --- Anel verde ---
      canvas.drawCircle(
        const Offset(cx, cy),
        r - 1.2,
        Paint()
          ..color = const Color(0xFF00E676)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8,
      );

      // --- Ícone do campo centrado ---
      final iconPainter = TextPainter(textDirection: TextDirection.ltr);
      iconPainter.text = TextSpan(
        text: String.fromCharCode(MapaIcons.soccer_field_svgrepo_com__2_.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: MapaIcons.soccer_field_svgrepo_com__2_.fontFamily,
          color: const Color(0xFF00E676),
        ),
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        Offset(cx - iconPainter.width / 2, cy - iconPainter.height / 2),
      );

      final img = await recorder.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      _iconeQuadraParceira = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
      return _iconeQuadraParceira!;
    } catch (e) {
      debugPrint('Erro ícone quadra: $e');
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
  }

  Future<void> _carregarQuadrasParceiras() async {
    try {
      final icone = await _gerarIconeQuadraParceira();
      final snapshot = await FirebaseFirestore.instance
          .collection('quadras')
          .where('aprovada', isEqualTo: true)
          .get();

      final Set<Marker> novosPinos = {};
      _quadrasMeta.clear();

      for (final doc in snapshot.docs) {
        final dados = doc.data();
        final double? lat = (dados['latitude'] as num?)?.toDouble();
        final double? lng = (dados['longitude'] as num?)?.toDouble();
        final String nome = dados['nome']?.toString() ?? 'Quadra Parceira';
        final String endereco = dados['endereco']?.toString() ?? '';

        if (lat == null || lng == null) continue;

        _quadrasMeta[doc.id] = {
          'nome': nome,
          'endereco': endereco,
          'lat': lat,
          'lng': lng,
        };

        final id = doc.id;
        novosPinos.add(
          Marker(
            markerId: MarkerId(id),
            position: LatLng(lat, lng),
            // Âncora na ponta da gota (centro-baixo)
            anchor: const Offset(0.5, 1.0),
            icon: icone,
            consumeTapEvents: true,
            onTap: () => _onTapQuadraParceira(id),
          ),
        );
      }

      if (mounted) setState(() => _pinosQuadras = novosPinos);
    } catch (e) {
      debugPrint('Erro quadras: $e');
    }
  }

  /// Toque no pin: se houver vizinhas a &lt; 100 m, lista para escolher; senão confirma direto.
  void _onTapQuadraParceira(String idTocado) {
    final meta = _quadrasMeta[idTocado];
    if (meta == null) return;

    final lat = meta['lat'] as double;
    final lng = meta['lng'] as double;
    final nome = meta['nome'] as String;
    final endereco = meta['endereco'] as String? ?? '';

    final vizinhas = <Map<String, dynamic>>[];
    for (final entry in _quadrasMeta.entries) {
      final m = entry.value;
      final d = Geolocator.distanceBetween(
        lat,
        lng,
        m['lat'] as double,
        m['lng'] as double,
      );
      if (d <= _raioVizinhaMetros) {
        vizinhas.add({
          'id': entry.key,
          'nome': m['nome'],
          'endereco': m['endereco'] ?? '',
          'lat': m['lat'],
          'lng': m['lng'],
          'distanciaM': d.round(),
        });
      }
    }

    // Ordena: mais perto primeiro
    vizinhas.sort((a, b) => (a['distanciaM'] as int).compareTo(b['distanciaM'] as int));

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));

    if (vizinhas.length >= 2) {
      _chipQuadraVN.value = '${vizinhas.length} quadras aqui';
      _mostrarEscolhaQuadrasProximas(vizinhas);
    } else {
      _chipQuadraVN.value = nome;
      _abrirModalConfirmacao(
        nomeLocalInicial: nome,
        endereco: endereco,
        lat: lat,
        lng: lng,
        origemSelecao: 'mapa_pin',
      );
    }
  }

  void _mostrarEscolhaQuadrasProximas(List<Map<String, dynamic>> lista) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
          decoration: const BoxDecoration(
            color: Color(0xFF161616),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.stadium_rounded, color: Color(0xFF00E676), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Quadras neste ponto',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${lista.length} parceiras a menos de ${_raioVizinhaMetros.round()} m — escolhe uma:',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...lista.map((q) {
                final dist = q['distanciaM'] as int;
                final labelDist = dist < 5 ? 'Aqui' : '$dist m';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pop(ctx);
                        final n = q['nome'] as String;
                        _chipQuadraVN.value = n;
                        _abrirModalConfirmacao(
                          nomeLocalInicial: n,
                          endereco: q['endereco'] as String? ?? '',
                          lat: q['lat'] as double,
                          lng: q['lng'] as double,
                          origemSelecao: 'mapa_pin',
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withAlpha(28),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.sports_soccer,
                                color: Color(0xFF00E676),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    q['nome'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if ((q['endereco'] as String?)?.isNotEmpty == true)
                                    Text(
                                      q['endereco'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              labelDist,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Busca — só mexe em ValueNotifiers (mapa NÃO reconstrói).
  void _buscarEnderecoTexto(String texto) {
    _searchDebounce?.cancel();
    _temTextoBuscaVN.value = texto.isNotEmpty;

    final query = texto.trim();
    if (query.length < 3) {
      _previsoesVN.value = const [];
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _executarBuscaPlaces(query);
    });
  }

  Future<void> _executarBuscaPlaces(String query) async {
    final int seq = ++_searchSeq;

    final url = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': query,
      'types': 'geocode|establishment',
      'components': 'country:br',
      'key': _googleApiKey,
      'sessiontoken': _sessionToken,
      'language': 'pt-BR',
    });

    try {
      final response = await http.get(url);
      if (seq != _searchSeq || !mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _previsoesVN.value = List<dynamic>.from(data['predictions'] ?? const []);
      }
    } catch (e) {
      if (seq == _searchSeq) debugPrint('Erro na busca Places: $e');
    }
  }

  Future<void> _irParaLugarUid(String placeId, String nomePrincipal) async {
    FocusScope.of(context).unfocus();
    _previsoesVN.value = const [];
    _cBusca.clear();
    _temTextoBuscaVN.value = false;
    _carregandoGpsVN.value = true;
    _chipQuadraVN.value = null;

    final url = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': 'geometry,name,formatted_address',
      'key': _googleApiKey,
      'sessiontoken': _sessionToken,
      'language': 'pt-BR',
    });

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = data['result']['geometry']['location'];
        final LatLng novaPos = LatLng(loc['lat'], loc['lng']);

        final String enderecoCompleto = data['result']['formatted_address'] ?? 'Endereço encontrado';
        final String nomeLugar = data['result']['name'] ?? nomePrincipal;

        if (mounted) {
          _posicaoAtual = novaPos;
          _ruaVN.value = enderecoCompleto;
          _nomeLocalVN.value = nomeLugar;
          _veioDaBusca = true;
          _carregandoGpsVN.value = false;
          _sessionToken = const Uuid().v4();
        }

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(novaPos, 16));

        if (nomeLugar != enderecoCompleto && !nomeLugar.contains(RegExp(r'\d'))) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            _abrirModalConfirmacao(
              nomeLocalInicial: nomeLugar,
              endereco: enderecoCompleto,
              lat: novaPos.latitude,
              lng: novaPos.longitude,
              origemSelecao: 'busca_nome',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) _carregandoGpsVN.value = false;
      debugPrint('Erro detalhes: $e');
    }
  }

  Future<void> _pegarLocalizacaoAtual() async {
    _carregandoGpsVN.value = true;
    _chipQuadraVN.value = null;

    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) {
      if (mounted) _carregandoGpsVN.value = false;
      return;
    }

    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
      if (permissao == LocationPermission.denied) {
        if (mounted) _carregandoGpsVN.value = false;
        return;
      }
    }

    final Position pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      _posicaoAtual = LatLng(pos.latitude, pos.longitude);
      _carregandoGpsVN.value = false;
      _veioDaBusca = false;
    }

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_posicaoAtual, 16));
    _atualizarEnderecoRua(_posicaoAtual);
  }

  void _onCameraIdleOtimizado() {
    _movendoVN.value = false;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _atualizarEnderecoRua(_posicaoAtual);
    });
  }

  Future<void> _atualizarEnderecoRua(LatLng pos) async {
    if (_veioDaBusca) {
      _veioDaBusca = false;
      return;
    }

    try {
      final locais = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (locais.isNotEmpty && mounted) {
        final lugar = locais.first;
        String rua = lugar.thoroughfare ?? lugar.street ?? 'Endereço desconhecido';
        final numero = lugar.subThoroughfare ?? '';
        final bairro = lugar.subLocality ?? lugar.locality ?? '';
        var enderecoCompleto = rua;
        if (numero.isNotEmpty && numero != 'S/N') enderecoCompleto += ', $numero';
        if (bairro.isNotEmpty) enderecoCompleto += ' - $bairro';

        _ruaVN.value = enderecoCompleto;
        final possivelNome = lugar.name ?? '';
        if (possivelNome.isNotEmpty &&
            possivelNome != numero &&
            !RegExp(r'^\d+$').hasMatch(possivelNome) &&
            possivelNome != rua) {
          _nomeLocalVN.value = possivelNome;
        } else {
          _nomeLocalVN.value = '';
        }
      }
    } catch (e) {
      if (mounted) {
        _ruaVN.value = 'Rua não encontrada (Mova o pino)';
        _nomeLocalVN.value = '';
      }
    }
  }

  void _abrirModalConfirmacao({
    String? nomeLocalInicial,
    required String endereco,
    required double lat,
    required double lng,
    String? obsInicial,
    String? origemSelecao,
  }) {
    final origem = origemSelecao ?? (_veioDaBusca ? 'busca_nome' : 'mapa_pin');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModalDetalhesQuadra(
        nomeLocalInicial: nomeLocalInicial,
        endereco: endereco,
        lat: lat,
        lng: lng,
        obsInicial: obsInicial,
        origemSelecao: origem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      // Teclado NÃO redimensiona o mapa (evita rebuild nativo caro)
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // ===== MAPA: só reconstrói quando markers mudam (load inicial) =====
          GoogleMap(
            padding: EdgeInsets.only(top: topPad + 80, bottom: bottomPad + 90),
            style: _mapStyle,
            initialCameraPosition: CameraPosition(target: _posicaoAtual, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            markers: _pinosQuadras,
            onMapCreated: (c) => _mapController = c,
            onCameraMoveStarted: () {
              _movendoVN.value = true;
              _chipQuadraVN.value = null;
              if (!_veioDaBusca) FocusScope.of(context).unfocus();
            },
            onCameraMove: (pos) => _posicaoAtual = pos.target,
            onCameraIdle: _onCameraIdleOtimizado,
          ),

          // ===== Label central (endereço) — ValueListenable, sem setState =====
          ValueListenableBuilder<bool>(
            valueListenable: _movendoVN,
            builder: (_, movendo, __) {
              return ValueListenableBuilder<String>(
                valueListenable: _ruaVN,
                builder: (_, rua, __) {
                  return ValueListenableBuilder<String>(
                    valueListenable: _nomeLocalVN,
                    builder: (_, nome, __) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedOpacity(
                            opacity: movendo ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 32),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (nome.isNotEmpty)
                                    Text(
                                      nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  Text(
                                    rua,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: nome.isNotEmpty ? Colors.white70 : Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Icon(Icons.location_on, size: 26, color: Color(0xFF00E676)),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),

          // ===== Chip nome da quadra parceira (só ao tocar no pin) =====
          ValueListenableBuilder<String?>(
            valueListenable: _chipQuadraVN,
            builder: (_, chip, __) {
              if (chip == null) return const SizedBox.shrink();
              return Positioned(
                top: topPad + 78,
                left: 24,
                right: 24,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xF0121212),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00E676).withAlpha(160)),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.stadium_rounded, color: Color(0xFF00E676), size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              chip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // ===== Barra de busca + previsões (isolada do mapa) =====
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: TextField(
                          controller: _cBusca,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          onChanged: _buscarEnderecoTexto,
                          decoration: InputDecoration(
                            hintText: 'Digite o endereço ou nome da arena...',
                            hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                            prefixIcon: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            suffixIcon: ValueListenableBuilder<bool>(
                              valueListenable: _temTextoBuscaVN,
                              builder: (_, tem, __) {
                                if (!tem) {
                                  return const Icon(Icons.search, color: Color(0xFF00E676));
                                }
                                return IconButton(
                                  icon: const Icon(Icons.close, color: Colors.grey),
                                  onPressed: () {
                                    _cBusca.clear();
                                    _previsoesVN.value = const [];
                                    _temTextoBuscaVN.value = false;
                                  },
                                );
                              },
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      ValueListenableBuilder<List<dynamic>>(
                        valueListenable: _previsoesVN,
                        builder: (_, previsoes, __) {
                          if (previsoes.isEmpty) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            constraints: const BoxConstraints(maxHeight: 280),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                              ],
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: previsoes.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: Colors.white10, height: 1),
                              itemBuilder: (context, index) {
                                final p = previsoes[index];
                                final main = p['structured_formatting']?['main_text'] ?? '';
                                final secondary =
                                    p['structured_formatting']?['secondary_text'] ?? '';
                                return ListTile(
                                  leading: const Icon(Icons.location_on, color: Colors.grey, size: 20),
                                  title: Text(
                                    main,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    secondary,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  onTap: () => _irParaLugarUid(p['place_id'], main),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 100,
                  right: 20,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _carregandoGpsVN,
                    builder: (_, carregando, __) {
                      return FloatingActionButton(
                        backgroundColor: const Color(0xFF1E1E1E),
                        elevation: 4,
                        onPressed: _pegarLocalizacaoAtual,
                        child: carregando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF00E676),
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location, color: Color(0xFF00E676)),
                      );
                    },
                  ),
                ),

                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        _abrirModalConfirmacao(
                          nomeLocalInicial: _nomeLocalVN.value,
                          endereco: _ruaVN.value,
                          lat: _posicaoAtual.latitude,
                          lng: _posicaoAtual.longitude,
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.black, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'USAR ESTE LOCAL',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 🚀 CLASS ISOLADA DO MODAL: Isso impede que o mapa seja forçado a se redesenhar quando o teclado abre!
class _ModalDetalhesQuadra extends StatefulWidget {
  final String? nomeLocalInicial;
  final String endereco;
  final double lat;
  final double lng;
  final String? obsInicial;
  /// 'busca_nome' = veio da barra de busca Places | 'mapa_pin' = pin/GPS/arraste
  final String origemSelecao;

  const _ModalDetalhesQuadra({
    this.nomeLocalInicial,
    required this.endereco,
    required this.lat,
    required this.lng,
    this.obsInicial,
    this.origemSelecao = 'mapa_pin',
  });

  @override
  State<_ModalDetalhesQuadra> createState() => _ModalDetalhesQuadraState();
}

class _ModalDetalhesQuadraState extends State<_ModalDetalhesQuadra> {
  late TextEditingController cNome;
  late TextEditingController cObs;

  @override
  void initState() {
    super.initState();
    cNome = TextEditingController(text: widget.nomeLocalInicial ?? '');
    cObs = TextEditingController(text: widget.obsInicial ?? '');
  }

  @override
  void dispose() {
    cNome.dispose();
    cObs.dispose();
    super.dispose(); // 👈 Deixe apenas esse super.dispose()!
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ), 
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            
            const Text("Detalhes da Quadra", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.white54, size: 14),
                const SizedBox(width: 4),
                Expanded(child: Text(widget.endereco, style: const TextStyle(color: Colors.white54, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 20),

            TextField(
              controller: cNome,
              autofocus: widget.nomeLocalInicial == null || widget.nomeLocalInicial!.isEmpty, 
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "Ex: Arena do Grêmio, Society do Zé...",
                hintStyle: const TextStyle(color: Colors.white24, fontWeight: FontWeight.normal),
                labelText: "Nome do Local",
                labelStyle: const TextStyle(color: Color(0xFF00E676)),
                prefixIcon: const Icon(Icons.sports_soccer, color: Color(0xFF00E676), size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: cObs,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Ex: Campo 3, Perto da churrasqueira",
                hintStyle: const TextStyle(color: Colors.white24),
                labelText: "Observação (Opcional)",
                labelStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.edit_note, color: Colors.grey, size: 18),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (cNome.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O nome da quadra é obrigatório!"), backgroundColor: Colors.orangeAccent));
                    return;
                  }
                    final nav = Navigator.of(context);
                    nav.pop(); // Fecha o modal
                    nav.pop({  // Fecha a página do mapa devolvendo o resultado
                      'nomeLocal': cNome.text.trim(),
                      'enderecoRua': widget.endereco,
                      'obs': cObs.text.trim(),
                      'lat': widget.lat,
                      'lng': widget.lng,
                      'origemSelecao': widget.origemSelecao, // busca_nome | mapa_pin
                    });
                },
                child: const Text("CONFIRMAR E SALVAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
              ),
            )
          ],
        ),
      ),
    );
  }
}