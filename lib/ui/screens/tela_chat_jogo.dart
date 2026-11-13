import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TelaChatJogo extends StatefulWidget {
  final String idJogo;
  final String nomeDestinatario;
  final DateTime dataHoraJogo;
  final int duracaoJogo;

  const TelaChatJogo({
    super.key,
    required this.idJogo,
    required this.nomeDestinatario,
    required this.dataHoraJogo,
    required this.duracaoJogo,
  });

  @override
  State<TelaChatJogo> createState() => _TelaChatJogoState();
}

class _TelaChatJogoState extends State<TelaChatJogo> {
  final TextEditingController _mensagemController = TextEditingController();
  final String _idUsuarioAtual = FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Notifiers: teclado / status não forçam rebuild de toda a lista de mensagens
  final ValueNotifier<bool> _enviandoVN = ValueNotifier(false);
  final ValueNotifier<String> _statusJogoVN = ValueNotifier('');

  late final Stream<QuerySnapshot> _mensagensStream;
  StreamSubscription<QuerySnapshot>? _marcarLidasSubscription;
  StreamSubscription<DocumentSnapshot>? _jogoSubscription;

  @override
  void initState() {
    super.initState();

    _mensagensStream = FirebaseFirestore.instance
        .collection('jogos')
        .doc(widget.idJogo)
        .collection('mensagens')
        .orderBy('dataEnvio', descending: true)
        .snapshots();

    _escutarEMarcarLidas();
    _escutarStatusDoJogo();
  }

  @override
  void dispose() {
    _marcarLidasSubscription?.cancel();
    _jogoSubscription?.cancel();
    _mensagemController.dispose();
    _enviandoVN.dispose();
    _statusJogoVN.dispose();
    super.dispose();
  }

  void _escutarStatusDoJogo() {
    _jogoSubscription = FirebaseFirestore.instance
        .collection('jogos')
        .doc(widget.idJogo)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        _statusJogoVN.value = snapshot.data()?['status']?.toString() ?? '';
      }
    });
  }

  void _escutarEMarcarLidas() {
    _marcarLidasSubscription = FirebaseFirestore.instance
        .collection('jogos')
        .doc(widget.idJogo)
        .collection('mensagens')
        .where('idRemetente', isNotEqualTo: _idUsuarioAtual)
        .where('lida', isEqualTo: false)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'lida': true});
        }
        await batch.commit();
      }
    });
  }

  bool _estaBloqueado(String status) {
    if (status == 'cancelado' ||
        status == 'contestado' ||
        status == 'em_disputa' ||
        status == 'expirado' ||
        status == 'finalizado') {
      return true;
    }
    final fimDaPartida =
        widget.dataHoraJogo.add(Duration(minutes: widget.duracaoJogo));
    final limiteChat = fimDaPartida.add(const Duration(hours: 1));
    return DateTime.now().isAfter(limiteChat);
  }

  Future<void> _enviarMensagem() async {
    final texto = _mensagemController.text.trim();
    if (texto.isEmpty || _estaBloqueado(_statusJogoVN.value)) return;
    if (_enviandoVN.value) return;

    _enviandoVN.value = true;

    try {
      await FirebaseFirestore.instance
          .collection('jogos')
          .doc(widget.idJogo)
          .collection('mensagens')
          .add({
        'texto': texto,
        'idRemetente': _idUsuarioAtual,
        'dataEnvio': FieldValue.serverTimestamp(),
        'lida': false,
      });

      _mensagemController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao enviar mensagem. Tente novamente.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) _enviandoVN.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161616),
      // true = input sobe com o teclado (comportamento certo no chat)
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF333333),
              radius: 16,
              child: Icon(Icons.person, color: Colors.white54, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.nomeDestinatario,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _mensagensStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Erro ao carregar chat',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00E676)),
                  );
                }

                final mensagens = snapshot.data?.docs ?? [];

                if (mensagens.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 60,
                          color: Colors.white.withAlpha(20),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhuma mensagem ainda.',
                          style: TextStyle(color: Colors.white54),
                        ),
                        const Text(
                          'Inicie a conversa!',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                // LayoutBuilder: largura dos balões SEM depender de MediaQuery
                // (teclado muda viewInsets → MediaQuery rebuildia TODOS os itens)
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final maxBubble = constraints.maxWidth * 0.75;
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      // keyboardDismissBehavior: ao arrastar a lista, baixa o teclado
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: mensagens.length,
                      itemBuilder: (context, index) {
                        final dados =
                            mensagens[index].data() as Map<String, dynamic>;
                        final bool souEu =
                            dados['idRemetente'] == _idUsuarioAtual;

                        DateTime? dataEnvio;
                        if (dados['dataEnvio'] != null) {
                          dataEnvio =
                              (dados['dataEnvio'] as Timestamp).toDate();
                        }

                        return _BalaoMensagem(
                          texto: dados['texto']?.toString() ?? '',
                          souEu: souEu,
                          data: dataEnvio,
                          maxWidth: maxBubble,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // Rodapé: só este pedaço reage a status / enviando
          SafeArea(
            child: ValueListenableBuilder<String>(
              valueListenable: _statusJogoVN,
              builder: (_, status, __) {
                if (_estaBloqueado(status)) {
                  return _buildAvisoChatBloqueado();
                }
                return _buildBarraDeDigitacao();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraDeDigitacao() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _mensagemController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviarMensagem(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Digite sua mensagem...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: _enviandoVN,
            builder: (_, enviando, __) {
              return CircleAvatar(
                backgroundColor: const Color(0xFF00E676),
                radius: 24,
                child: enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                        onPressed: _enviarMensagem,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoChatBloqueado() {
    final status = _statusJogoVN.value;
    final isCancelado = status == 'cancelado';
    final isDisputa = status == 'contestado' || status == 'em_disputa';

    String mensagem = 'Chat encerrado. Mensagens apenas para leitura.';
    Color corIcone = Colors.white54;
    IconData icone = Icons.lock_outline;

    if (isCancelado) {
      mensagem = 'Chat indisponível (Partida cancelada).';
      corIcone = Colors.redAccent;
      icone = Icons.block;
    } else if (isDisputa) {
      mensagem = 'Chat bloqueado (Partida em contestação).';
      corIcone = Colors.orangeAccent;
      icone = Icons.gavel_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isCancelado || isDisputa)
            ? corIcone.withAlpha(20)
            : const Color(0xFF1E1E1E),
        border: Border(
          top: BorderSide(
            color: (isCancelado || isDisputa)
                ? corIcone.withAlpha(50)
                : Colors.white10,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, color: corIcone, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              mensagem,
              style: TextStyle(
                color: corIcone,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Balão isolado — não depende de MediaQuery (evita lag ao abrir teclado).
class _BalaoMensagem extends StatelessWidget {
  final String texto;
  final bool souEu;
  final DateTime? data;
  final double maxWidth;

  const _BalaoMensagem({
    required this.texto,
    required this.souEu,
    required this.data,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: souEu ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: souEu ? const Color(0xFF00E676) : const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(souEu ? 16 : 0),
            bottomRight: Radius.circular(souEu ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              souEu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              style: TextStyle(
                color: souEu ? Colors.black : Colors.white,
                fontSize: 14,
              ),
            ),
            if (data != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(data!),
                style: TextStyle(
                  color: souEu ? Colors.black54 : Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
