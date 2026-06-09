import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  Set<Marker> _pinosQuadras = {}; // 🔥 Guarda os pinos das quadras do Firebase
  BitmapDescriptor? _iconeQuadraParceira; // 🔥 Vai guardar a imagem customizada

  // Controles dos novos campos separados
  final TextEditingController _cNomeQuadra = TextEditingController();
  final TextEditingController _cObsQuadra = TextEditingController();
  final TextEditingController _cBusca = TextEditingController();

  // Controle de economia do Google (Session Token)
  String _sessionToken = const Uuid().v4();
  List<dynamic> _previsoesBusca = [];

  // Chave do Google (O código vai puxar direto do manifesto, mas se der erro, coloque sua string aqui)
  final String _googleApiKey = "AIzaSyCE_x3Zho8A4vcGGXmvCHV0DWCtlDZhYtA"; 

  final String _mapStyle = '''[{"elementType": "geometry", "stylers": [{"color": "#212121"}]},{"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},{"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},{"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]}]''';

@override
void initState() {
  super.initState();
  _pegarLocalizacaoAtual();
  
  // Garante que o Flutter já está pronto para desenhar imagens antes de carregar o ícone
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _criarIconeCustomizado();
  });
}

  @override
  void dispose() {
    _cNomeQuadra.dispose();
    _cObsQuadra.dispose();
    _cBusca.dispose();
    super.dispose();
  }

Future<void> _criarIconeCustomizado() async {
  // Ajusta o tamanho ideal para o pino não ficar gigante na tela (ex: 100 de largura)
  final ImageConfiguration config = createLocalImageConfiguration(context, size: const Size(100, 100));
  
  final icone = await BitmapDescriptor.fromAssetImage(
    config, 
    'assets/images/bola_pino.png' // ⚽ Caminho da sua imagem!
  );
  
  setState(() {
    _iconeQuadraParceira = icone;
  });
  
  // Depois que o ícone carregar na memória, aí sim buscamos os pinos do Firebase!
  _carregarQuadrasParceiras(); 
}

  Future<void> _carregarQuadrasParceiras() async {
  try {
    // Busca todas as quadras ativas no seu Firestore
    final snapshot = await FirebaseFirestore.instance.collection('quadras').get();
    
    Set<Marker> novosPinos = {};

    for (var doc in snapshot.docs) {
      final dados = doc.data();
      final double? lat = dados['latitude']?.toDouble();
      final double? lng = dados['longitude']?.toDouble();
      final String nome = dados['nome'] ?? 'Quadra Parceira';
      final String endereco = dados['endereco'] ?? '';

      // Se a quadra tiver coordenadas válidas, cria o pino dela
      if (lat != null && lng != null) {
        novosPinos.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: _iconeQuadraParceira ?? BitmapDescriptor.defaultMarkerWithHue(145.0),
            // 🟢 Dentro de _carregarQuadrasParceiras(), procure o InfoWindow:
infoWindow: InfoWindow(
  title: nome,
  snippet: "Toque para selecionar esta quadra",
  onTap: () {
    Navigator.pop(context, {
      'nomeLocal': nome,         // 👈 Garante que envia o NOME real da quadra (Ex: Arena Soccer)
      'enderecoRua': endereco,   // 👈 Garante que envia a RUA/ENDEREÇO separado
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
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$texto&types=geocode|establishment&key=$_googleApiKey&sessiontoken=$_sessionToken&language=pt-BR'
    );

    try {
      final response = await http.get(url);
      
      // 🔴 COLOQUE ESTA LINHA AQUI PARA VER O ERRO NO TERMINAL DO VSCODE/ANDROID STUDIO:
      debugPrint("RETORNO GOOGLE PLACES: ${response.body}");

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

  // ✈️ MOVE O MAPA PARA O LUGAR CLICADO NA BUSCA
  Future<void> _irParaLugarUid(String placeId, String nomePrincipal) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _previsoesBusca = [];
      _cBusca.clear();
    });

    final url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name&key=$_googleApiKey&sessiontoken=$_sessionToken');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = data['result']['geometry']['location'];
        final LatLng novaPos = LatLng(loc['lat'], loc['lng']);

        setState(() {
          _posicaoAtual = novaPos;
          // Se o usuário clicou num estabelecimento (ex: "Arena Soccer"), já preenche o nome!
          _cNomeQuadra.text = nomePrincipal; 
          _sessionToken = const Uuid().v4(); // Renova o token para a próxima busca
        });

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(novaPos, 16));
        _atualizarEnderecoRua(novaPos);
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
    });

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_posicaoAtual, 16));
    _atualizarEnderecoRua(_posicaoAtual);
  }

Future<void> _atualizarEnderecoRua(LatLng pos) async {
    try {
      List<Placemark> locais = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (locais.isNotEmpty) {
        Placemark lugar = locais.first;
        
        setState(() {
          String rua = lugar.thoroughfare ?? lugar.street ?? "Endereço desconhecido";
          String numero = lugar.subThoroughfare ?? ""; // 🟢 AQUI ESTÁ A MÁGICA DO NÚMERO!
          String bairro = lugar.subLocality ?? lugar.locality ?? "";
          
          // Monta o endereço no padrão brasileiro
          String enderecoCompleto = rua;
          
          // Se o Google achar o número, adiciona com vírgula
          if (numero.isNotEmpty && numero != "S/N") {
            enderecoCompleto += ", $numero";
          }
          
          // Adiciona o bairro com um tracinho
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
          // 1. MAPA EM TELA CHEIA (Fica fora do SafeArea para o efeito de fundo infinito)
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _posicaoAtual, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            markers: _pinosQuadras,
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController?.setMapStyle(_mapStyle);
            },
            onCameraIdle: () => _atualizarEnderecoRua(_posicaoAtual),
            onCameraMove: (pos) => _posicaoAtual = pos.target,
          ),

          // 2. PINO FIXO NO MEIO (Fica fora do SafeArea para centralizar perfeitamente no mapa)
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on, size: 50, color: Color(0xFF00E676)),
              SizedBox(height: 50),
            ],
          ),

          // 🟢 ARMADURA: Protege APENAS os itens da interface
          SafeArea(
            child: Stack(
              children: [
                // 3. 🔍 BARRA DE BUSCA COMPLETA (NO TOPO)
                Positioned(
                  top: 10, // Agora o top não precisa ser "50", o SafeArea já faz o distanciamento da câmera
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
                      
                      // Lista suspensa de resultados da busca
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

                // Botão GPS atual
                Positioned(
                  bottom: 290, // Subimos um pouquinho pra não colar no painel
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF1E1E1E),
                    mini: true,
                    child: const Icon(Icons.my_location, color: Color(0xFF00E676)),
                    onPressed: () => _pegarLocalizacaoAtual(),
                  ),
                ),

                // 4. 🏢 NOVO PAINEL INFERIOR COM CAMPOS DA QUADRA E OBSERVAÇÕES
                Positioned(
                  bottom: 10, // Agora o bottom fica baixinho, pois o SafeArea protege contra a navegação
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
                        // Exibe a rua atual onde o pino está em cima
                        Text(_ruaEletro, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 12),

                        // Campo 1: Nome da Quadra (Obrigatório para o nosso Crowdsourcing!)
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

                        // Campo 2: Observações específicas
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

                        // Botão de Confirmação Final
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              // Validação básica: Não deixa salvar sem dar um nome para o local
                              if (_cNomeQuadra.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Dê um nome para a Quadra/Local!"), backgroundColor: Colors.orangeAccent)
                                );
                                return;
                              }

                              // Devolve tudo mastigadinho para a tela de criação
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