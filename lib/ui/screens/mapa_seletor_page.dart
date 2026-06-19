import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:defendepramim/core/chaves.dart'; // 🟢 Ajuste o caminho se precisar
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

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
  Set<Marker> _pinosQuadras = {}; 
  BitmapDescriptor? _iconeQuadraParceira; // 🟢 Armazena o ícone customizado convertido

  // 🟢 TRAVA DE PROTEÇÃO DO GOOGLE PLACES
  bool _veioDaBusca = false;

  final TextEditingController _cNomeQuadra = TextEditingController();
  final TextEditingController _cObsQuadra = TextEditingController();
  final TextEditingController _cBusca = TextEditingController();

  String _sessionToken = const Uuid().v4();
  List<dynamic> _previsoesBusca = [];

  // 🟢 Puxa direto do código compilado:
  final String _googleApiKey = ChavesSecretas.googleApiKey;

  final String _mapStyle = '''[{"elementType": "geometry", "stylers": [{"color": "#212121"}]},{"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},{"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},{"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]}]''';

  @override
  void initState() {
    super.initState();
    _pegarLocalizacaoAtual();
    
    // 🟢 Dispara o carregamento do ícone logo na inicialização
    _inicializarIconeEQuadras();
  }

  @override
  void dispose() {
    _cNomeQuadra.dispose();
    _cObsQuadra.dispose();
    _cBusca.dispose();
    super.dispose();
  }

  // 🟢 FUNÇÃO COMBINADA: Garante que o ícone carregue antes de buscar os dados do Firebase
  // 🟢 FUNÇÃO COMBINADA: Garante que o ícone carregue antes de buscar os dados do Firebase
  Future<void> _inicializarIconeEQuadras() async {
    try {
      // Abre o arquivo de imagem bruto
      ByteData data = await rootBundle.load('assets/bola_pino.png');
      
      // 🔴 REDUZIDO AQUI: Mudamos de 120 para 55 para ficar bem ajustado e nítido no mapa!
      ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 55);
      
      ui.FrameInfo fi = await codec.getNextFrame();
      final bytes = await fi.image.toByteData(format: ui.ImageByteFormat.png);
      
      if (bytes != null) {
        setState(() {
          _iconeQuadraParceira = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
        });
        debugPrint("⚽ ÍCONE CUSTOMIZADO COMPACTADO COM SUCESSO!");
      }
    } catch (e) {
      debugPrint("🚨 Erro ao converter imagem do asset: $e");
    }

    // Mesmo se a imagem falhar, busca as quadras para usar o pino verde como plano B
    _carregarQuadrasParceiras();
  }

  Future<void> _carregarQuadrasParceiras() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('quadras')
          .where('aprovada', isEqualTo: true)
          .get();
          
      Set<Marker> novosPinos = {};

      for (var doc in snapshot.docs) {
        final dados = doc.data();
        
        final double? lat = dados['latitude']?.toDouble();
        final double? lng = dados['longitude']?.toDouble();
        final String nome = dados['nome'] ?? 'Quadra Parceira';
        final String endereco = dados['endereco'] ?? '';

        if (lat != null && lng != null) {
          novosPinos.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(lat, lng),
              
              // 🟢 SE O ÍCONE CUSTOMIZADO ESTIVER PRONTO, ELE USA. SE NÃO, ATIVA O VERDE NATIVO.
              icon: _iconeQuadraParceira ?? BitmapDescriptor.defaultMarkerWithHue(145.0),
              
              infoWindow: InfoWindow(
                title: nome,
                snippet: "Toque para selecionar esta quadra",
                onTap: () {
                  Navigator.pop(context, {
                    'nomeLocal': nome,      
                    'enderecoRua': endereco,  
                    'obs': dados['observacoes'] ?? '',
                    'lat': lat,
                    'lng': lng,
                  });
                },
              ),
            ),
          );
        }
      }

      setState(() {
        _pinosQuadras = novosPinos;
      });

    } catch (e) {
      debugPrint("Erro ao carregar quadras parceiras: $e");
    }
  }

  Future<void> _buscarEnderecoTexto(String texto) async {
    if (texto.isEmpty) {
      setState(() => _previsoesBusca = []);
      return;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$texto&types=geocode|establishment&components=country:br&key=$_googleApiKey&sessiontoken=$_sessionToken&language=pt-BR'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _previsoesBusca = data['predictions'] ?? [];
        });
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
    });

    final url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name,formatted_address&key=$_googleApiKey&sessiontoken=$_sessionToken&language=pt-BR');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = data['result']['geometry']['location'];
        final LatLng novaPos = LatLng(loc['lat'], loc['lng']);
        
        final String nomeLugar = data['result']['name'] ?? nomePrincipal;
        final String enderecoCompleto = data['result']['formatted_address'] ?? "Endereço encontrado";

        setState(() {
          _posicaoAtual = novaPos;
          _cNomeQuadra.text = nomeLugar; 
          _ruaEletro = enderecoCompleto; 
          _veioDaBusca = true; 
          _sessionToken = const Uuid().v4(); 
        });

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(novaPos, 16));
      }
    } catch (e) {
      debugPrint("Erro ao pegar detalhes: $e");
    }
  }

  Future<void> _pegarLocalizacaoAtual() async {
    bool servicoAtivo = await Geolocator.isLocationServiceEnabled();
    if (!servicoAtivo) return;

    LocationPermission permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
      if (permissao == LocationPermission.denied) return;
    }

    Position pos = await Geolocator.getCurrentPosition();
    setState(() {
      _posicaoAtual = LatLng(pos.latitude, pos.longitude);
      _carregandoLocalizacao = false;
      _veioDaBusca = false; 
    });

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_posicaoAtual, 16));
    _atualizarEnderecoRua(_posicaoAtual);
  }

  Future<void> _atualizarEnderecoRua(LatLng pos) async {
    if (_veioDaBusca) {
      _veioDaBusca = false; 
      return; 
    }

    try {
      List<Placemark> locais = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (locais.isNotEmpty) {
        Placemark lugar = locais.first;
        
        setState(() {
          String rua = lugar.thoroughfare ?? lugar.street ?? "Endereço desconhecido";
          String numero = lugar.subThoroughfare ?? ""; 
          String bairro = lugar.subLocality ?? lugar.locality ?? "";
          
          String enderecoCompleto = rua;
          
          if (numero.isNotEmpty && numero != "S/N") {
            enderecoCompleto += ", $numero";
          }
          if (bairro.isNotEmpty) {
            enderecoCompleto += " - $bairro";
          }
          
          _ruaEletro = enderecoCompleto;
        });
      }
    } catch (e) {
      setState(() => _ruaEletro = "Coordenadas: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            style: _mapStyle,
            initialCameraPosition: CameraPosition(target: _posicaoAtual, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            markers: _pinosQuadras,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraIdle: () => _atualizarEnderecoRua(_posicaoAtual),
            onCameraMoveStarted: () {
              if (!_veioDaBusca) {
                FocusScope.of(context).unfocus();
              }
            },
            onCameraMove: (pos) => _posicaoAtual = pos.target,
          ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _carregandoLocalizacao 
                  ? const SizedBox(height: 50, width: 50, child: CircularProgressIndicator(color: Color(0xFF00E676)))
                  : const Icon(Icons.location_on, size: 50, color: Color(0xFF00E676)),
              const SizedBox(height: 50),
            ],
          ),

          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 10, 
                  left: 20,
                  right: 20,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]
                        ),
                        child: TextField(
                          controller: _cBusca,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (val) => _buscarEnderecoTexto(val),
                          decoration: InputDecoration(
                            hintText: "Buscar rua, bairro ou arena...",
                            hintStyle: const TextStyle(color: Colors.white54),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF00E676)),
                            suffixIcon: _cBusca.text.isNotEmpty 
                              ? IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => setState(() { _cBusca.clear(); _previsoesBusca = []; }))
                              : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                      
                      if (_previsoesBusca.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          constraints: const BoxConstraints(maxHeight: 250),
                          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _previsoesBusca.length,
                            itemBuilder: (context, index) {
                              final p = _previsoesBusca[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on, color: Colors.grey, size: 18),
                                title: Text(p['structured_formatting']['main_text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                  bottom: 290, 
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF1E1E1E),
                    mini: true,
                    child: const Icon(Icons.my_location, color: Color(0xFF00E676)),
                    onPressed: () => _pegarLocalizacaoAtual(),
                  ),
                ),

                Positioned(
                  bottom: 10, 
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 2)]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_ruaEletro, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 12),

                        TextField(
                          controller: _cNomeQuadra,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Nome do Estabelecimento / Quadra",
                            hintStyle: const TextStyle(color: Colors.white24),
                            prefixIcon: const Icon(Icons.sports_soccer, color: Color(0xFF00E676), size: 18),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextField(
                          controller: _cObsQuadra,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: "Observações (Ex: Quadra 3, Churrasqueira)",
                            hintStyle: const TextStyle(color: Colors.white24),
                            prefixIcon: const Icon(Icons.edit_note, color: Colors.grey, size: 18),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_cNomeQuadra.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Dê um nome para a Quadra/Local!"), backgroundColor: Colors.orangeAccent)
                                );
                                return;
                              }

                              Navigator.pop(context, {
                                'nomeLocal': _cNomeQuadra.text.trim(),
                                'enderecoRua': _ruaEletro,
                                'obs': _cObsQuadra.text.trim(),
                                'lat': _posicaoAtual.latitude,
                                'lng': _posicaoAtual.longitude,
                              });
                            },
                            child: const Text("CONFIRMAR LOCAL E DADOS", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                          ),
                        )
                      ],
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