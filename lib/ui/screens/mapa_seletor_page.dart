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
  String _ruaEletro = "Buscando endereço...";
  bool _carregandoLocalizacao = true;
  String _nomeLocalEletro = ""; 
  bool _movendoMapa = false; 
  Set<Marker> _pinosQuadras = {}; 

  // 🚀 CACHE DE ÍCONES: Evita regerar o Canvas de quadras já desenhadas!
  final Map<String, BitmapDescriptor> _iconeCache = {};

  bool _veioDaBusca = false;

  final TextEditingController _cBusca = TextEditingController();
  String _sessionToken = const Uuid().v4();
  List<dynamic> _previsoesBusca = [];

  final String _googleApiKey = ChavesSecretas.googleApiKey;
  final String _mapStyle = '''[{"elementType": "geometry", "stylers": [{"color": "#212121"}]},{"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},{"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},{"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]}]''';

  Timer? _debounceTimer; 

  @override
  void initState() {
    super.initState();
    _pegarLocalizacaoAtual();
  }

  @override
  void dispose() {
    _cBusca.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  bool _iconeCarregado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iconeCarregado) {
      _carregarQuadrasParceiras();
      _iconeCarregado = true;
    }
  }

  // 🟢 GERADOR DE ÍCONE COM CACHE
  Future<BitmapDescriptor> _gerarIconeComNome(String nomeQuadra) async {
    if (_iconeCache.containsKey(nomeQuadra)) {
      return _iconeCache[nomeQuadra]!;
    }

    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);

      TextPainter textPainter = TextPainter(
        textDirection: TextDirection.ltr, 
        textAlign: TextAlign.center
      );
      textPainter.text = TextSpan(
        text: nomeQuadra,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF00E676),
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();

      TextPainter iconPainter = TextPainter(textDirection: TextDirection.ltr);
      iconPainter.text = TextSpan(
        text: String.fromCharCode(MapaIcons.soccer_field_svgrepo_com__2_.codePoint),
        style: TextStyle(
          fontSize: 65,
          fontFamily: MapaIcons.soccer_field_svgrepo_com__2_.fontFamily,
          color: const Color(0xFF00E676),
        ),
      );
      iconPainter.layout();

      final double paddingX = 14.0;
      final double paddingY = 8.0;
      final double gap = 2.0;

      final double bgWidth = textPainter.width + (paddingX * 2);
      final double bgHeight = textPainter.height + (paddingY * 2);

      final double widthTotal = bgWidth > iconPainter.width ? bgWidth : iconPainter.width;
      final double heightTotal = bgHeight + gap + iconPainter.height;

      final double bgLeft = (widthTotal - bgWidth) / 2;
      final RRect pilula = RRect.fromRectAndRadius(
        Rect.fromLTWH(bgLeft, 0, bgWidth, bgHeight),
        const Radius.circular(16.0),
      );
      final Paint paintFundo = Paint()
        ..color = const Color(0xEE000000)
        ..isAntiAlias = true;
      canvas.drawRRect(pilula, paintFundo);

      textPainter.paint(canvas, Offset(bgLeft + paddingX, paddingY));

      final double iconLeft = (widthTotal - iconPainter.width) / 2;
      iconPainter.paint(canvas, Offset(iconLeft, bgHeight + gap));

      final img = await pictureRecorder.endRecording().toImage(widthTotal.toInt(), heightTotal.toInt());
      final finalBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      final descriptor = BitmapDescriptor.bytes(finalBytes!.buffer.asUint8List());
      _iconeCache[nomeQuadra] = descriptor; // Salva no cache!
      return descriptor;
    } catch (e) {
      return BitmapDescriptor.defaultMarkerWithHue(145.0);
    }
  }

  Future<void> _carregarQuadrasParceiras() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('quadras').where('aprovada', isEqualTo: true).get();
      Set<Marker> novosPinos = {};

      for (var doc in snapshot.docs) {
        final dados = doc.data();
        final double? lat = dados['latitude']?.toDouble();
        final double? lng = dados['longitude']?.toDouble();
        final String nome = dados['nome'] ?? 'Quadra Parceira';
        final String endereco = dados['endereco'] ?? '';

        if (lat != null && lng != null) {
          BitmapDescriptor iconePersonalizado = await _gerarIconeComNome(nome);

          novosPinos.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              anchor: const Offset(0.5, 1.0),
              icon: iconePersonalizado, 
              onTap: () {
                _abrirModalConfirmacao(
                  nomeLocalInicial: nome, 
                  endereco: endereco, 
                  lat: lat, 
                  lng: lng, 
                );
              },
            ),
          );
        }
      }
      if (mounted) setState(() => _pinosQuadras = novosPinos);
    } catch (e) {
      debugPrint("Erro quadras: $e");
    }
  }

  Future<void> _buscarEnderecoTexto(String texto) async {
    if (texto.isEmpty) {
      setState(() => _previsoesBusca = []);
      return;
    }
    final url = Uri.parse('https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$texto&types=geocode|establishment&components=country:br&key=$_googleApiKey&sessiontoken=$_sessionToken&language=pt-BR');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _previsoesBusca = data['predictions'] ?? []);
      }
    } catch (e) {
      debugPrint("Erro na busca: $e");
    }
  }

  Future<void> _irParaLugarUid(String placeId, String nomePrincipal) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _previsoesBusca = [];
      _cBusca.clear();
      _carregandoLocalizacao = true;
    });

    final url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name,formatted_address&key=$_googleApiKey&sessiontoken=$_sessionToken&language=pt-BR');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = data['result']['geometry']['location'];
        final LatLng novaPos = LatLng(loc['lat'], loc['lng']);
        
        final String enderecoCompleto = data['result']['formatted_address'] ?? "Endereço encontrado";
        final String nomeLugar = data['result']['name'] ?? nomePrincipal; 

        if (mounted) {
          setState(() {
            _posicaoAtual = novaPos;
            _ruaEletro = enderecoCompleto; 
            _nomeLocalEletro = nomeLugar;
            _veioDaBusca = true; 
            _carregandoLocalizacao = false;
            _sessionToken = const Uuid().v4(); 
          });
        }

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(novaPos, 16));

        if (nomeLugar != enderecoCompleto && !nomeLugar.contains(RegExp(r'\d'))) {
           Future.delayed(const Duration(milliseconds: 800), () {
             _abrirModalConfirmacao(nomeLocalInicial: nomeLugar, endereco: enderecoCompleto, lat: novaPos.latitude, lng: novaPos.longitude);
           });
        }

      }
    } catch (e) {
      if (mounted) setState(() => _carregandoLocalizacao = false);
      debugPrint("Erro detalhes: $e");
    }
  }

  Future<void> _pegarLocalizacaoAtual() async {
    setState(() => _carregandoLocalizacao = true);
    
    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) {
      if (mounted) setState(() => _carregandoLocalizacao = false);
      return;
    }

    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
      if (permissao == LocationPermission.denied) {
        if (mounted) setState(() => _carregandoLocalizacao = false);
        return;
      }
    }

    Position pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _posicaoAtual = LatLng(pos.latitude, pos.longitude);
        _carregandoLocalizacao = false;
        _veioDaBusca = false; 
      });
    }

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_posicaoAtual, 16));
    _atualizarEnderecoRua(_posicaoAtual);
  }

  void _onCameraIdleOtimizado() {
    if (mounted) setState(() => _movendoMapa = false);
    
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
      List<Placemark> locais = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (locais.isNotEmpty && mounted) {
        Placemark lugar = locais.first;
        setState(() {
          String rua = lugar.thoroughfare ?? lugar.street ?? "Endereço desconhecido";
          String numero = lugar.subThoroughfare ?? ""; 
          String bairro = lugar.subLocality ?? lugar.locality ?? "";
          String enderecoCompleto = rua;
          
          if (numero.isNotEmpty && numero != "S/N") enderecoCompleto += ", $numero";
          if (bairro.isNotEmpty) enderecoCompleto += " - $bairro";
          
          _ruaEletro = enderecoCompleto;

          String possivelNome = lugar.name ?? "";
          if (possivelNome.isNotEmpty && possivelNome != numero && !RegExp(r'^\d+$').hasMatch(possivelNome) && possivelNome != rua) {
            _nomeLocalEletro = possivelNome;
          } else {
            _nomeLocalEletro = ""; 
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ruaEletro = "Rua não encontrada (Mova o pino)";
          _nomeLocalEletro = "";
        });
      }
    }
  }

  void _abrirModalConfirmacao({String? nomeLocalInicial, required String endereco, required double lat, required double lng, String? obsInicial}) {
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // 🚀 EVITA O REDIMENSIONAMENTO DO MAPA AO ABRIR O TECLADO
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center, 
        children: [
          GoogleMap(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 80, 
              bottom: MediaQuery.of(context).padding.bottom + 90, 
            ),
            style: _mapStyle,
            initialCameraPosition: CameraPosition(target: _posicaoAtual, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            markers: _pinosQuadras,
            onMapCreated: (controller) => _mapController = controller,
            onCameraMoveStarted: () {
              if (mounted) setState(() => _movendoMapa = true);
              if (!_veioDaBusca) FocusScope.of(context).unfocus();
            },
            onCameraMove: (pos) => _posicaoAtual = pos.target,
            onCameraIdle: _onCameraIdleOtimizado,
          ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedOpacity(
                opacity: _movendoMapa ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_carregandoLocalizacao)
                        const Text("Buscando GPS...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))
                      else ...[
                        if (_nomeLocalEletro.isNotEmpty)
                          Text(_nomeLocalEletro, style: const TextStyle(color: Color(0xFF00E676), fontSize: 14, fontWeight: FontWeight.w900)),
                        
                        Text(
                          _ruaEletro, 
                          style: TextStyle(color: _nomeLocalEletro.isNotEmpty ? Colors.white70 : Colors.white, fontSize: 11, fontWeight: FontWeight.w600), 
                          textAlign: TextAlign.center
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6), 
              const Icon(Icons.location_on, size: 24, color: Color(0xFF00E676)), 
              const SizedBox(height: 24), 
            ],
          ),

          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 10, left: 20, right: 20,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))]
                        ),
                        child: TextField(
                          controller: _cBusca,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          onChanged: _buscarEnderecoTexto,
                          decoration: InputDecoration(
                            hintText: "Digite o endereço ou nome da arena...",
                            hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                            prefixIcon: IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                            suffixIcon: _cBusca.text.isNotEmpty 
                              ? IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => setState(() { _cBusca.clear(); _previsoesBusca = []; }))
                              : const Icon(Icons.search, color: Color(0xFF00E676)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      
                      if (_previsoesBusca.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          constraints: const BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E), 
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))]
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _previsoesBusca.length,
                            separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final p = _previsoesBusca[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on, color: Colors.grey, size: 20),
                                title: Text(p['structured_formatting']['main_text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                subtitle: Text(p['structured_formatting']['secondary_text'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                onTap: () => _irParaLugarUid(p['place_id'], p['structured_formatting']['main_text']),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                Positioned(
                  bottom: 100, right: 20,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF1E1E1E),
                    elevation: 4,
                    child: _carregandoLocalizacao 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF00E676), strokeWidth: 2))
                      : const Icon(Icons.my_location, color: Color(0xFF00E676)),
                    onPressed: _pegarLocalizacaoAtual,
                  ),
                ),

                Positioned(
                  bottom: 20, left: 20, right: 20,
                  child: SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        _abrirModalConfirmacao(nomeLocalInicial: _nomeLocalEletro, endereco: _ruaEletro, lat: _posicaoAtual.latitude, lng: _posicaoAtual.longitude);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.black, size: 22),
                          SizedBox(width: 8),
                          Text("USAR ESTE LOCAL", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
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

  const _ModalDetalhesQuadra({
    this.nomeLocalInicial,
    required this.endereco,
    required this.lat,
    required this.lng,
    this.obsInicial,
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