import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ModalAvaliacaoGoleiro extends StatefulWidget {
  final String idGoleiro;
  final String idJogo;
  final VoidCallback onContestarWO;
  final VoidCallback onSucessoAvaliacao;

  const ModalAvaliacaoGoleiro({
    super.key,
    required this.idGoleiro,
    required this.idJogo,
    required this.onContestarWO,
    required this.onSucessoAvaliacao,
  });

  @override
  State<ModalAvaliacaoGoleiro> createState() => _ModalAvaliacaoGoleiroState();
}

class _ModalAvaliacaoGoleiroState extends State<ModalAvaliacaoGoleiro> {
  bool _compareceu = true;
  bool _noHorario = true;
  int _estrelasPersonalidade = 5;
  int _estrelasTecnica = 5;
  final TextEditingController _comentarioController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _salvarAvaliacao(double notaStars, int pontosTotais) async {
    setState(() => _enviando = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final goleiroRef = FirebaseFirestore.instance.collection('usuarios').doc(widget.idGoleiro);

      // Contadores no perfil do GOLEIRO (quem recebe a nota)
      batch.set(goleiroRef, {
        'somaAvaliacoes': FieldValue.increment(notaStars),
        'somaNotasAvaliacoes': FieldValue.increment(notaStars),
        'totalAvaliacoes': FieldValue.increment(1),
      }, SetOptions(merge: true));

      final jogoRef = FirebaseFirestore.instance.collection('jogos').doc(widget.idJogo);
      batch.update(jogoRef, {
        'avaliacaoGoleiro': notaStars,
        'avaliacaoDetalhada': {
          'compareceu': _compareceu,
          'noHorario': _noHorario,
          'estrelasPersonalidade': _estrelasPersonalidade,
          'estrelasTecnica': _estrelasTecnica,
          'pontuacaoTotal': pontosTotais,
          'comentario': _comentarioController.text.trim(),
          'avaliadoEm': FieldValue.serverTimestamp(),
        }
      });

      // Dispara recalcularNivelGoleiro no servidor
      final avRef = FirebaseFirestore.instance.collection('avaliacoes_goleiros').doc();
      batch.set(avRef, {
        'id': avRef.id,
        'idGoleiro': widget.idGoleiro,
        'idJogo': widget.idJogo,
        'notaGeral': notaStars,
        'compareceu': _compareceu,
        'noHorario': _noHorario,
        'estrelasPersonalidade': _estrelasPersonalidade,
        'estrelasTecnica': _estrelasTecnica,
        'comentario': _comentarioController.text.trim(),
        'criadoEm': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        widget.onSucessoAvaliacao();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erro ao salvar avaliação."), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildSimNaoToggle(bool valor, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => onChanged(false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: !valor ? Colors.redAccent : Colors.black38,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
            ),
            child: Text("Não", style: TextStyle(color: !valor ? Colors.white : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        InkWell(
          onTap: () => onChanged(true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: valor ? const Color(0xFF00E676) : Colors.black38,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
            ),
            child: Text("Sim", style: TextStyle(color: valor ? Colors.black : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildStarPicker(int valorAtual, Function(int) onSelected) {
    return Row(
      children: List.generate(5, (index) {
        final starNum = index + 1;
        return IconButton(
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(),
          icon: Icon(
            starNum <= valorAtual ? Icons.star_rounded : Icons.star_border_rounded,
            color: Colors.amber, size: 28,
          ),
          onPressed: () => onSelected(starNum),
        );
      }),
    );
  }

@override
  Widget build(BuildContext context) {
    int pontosCompareceu = _compareceu ? 10 : 0;
    int pontosHorario = (_compareceu && _noHorario) ? 10 : 0;
    int pontosPersonalidade = _compareceu ? (_estrelasPersonalidade * 2) : 0;
    int pontosTecnica = _compareceu ? (_estrelasTecnica * 4) : 0;

    int pontuacaoTotal = pontosCompareceu + pontosHorario + pontosPersonalidade + pontosTecnica;
    double notaEquivalenteStars = pontuacaoTotal / 10.0;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      // 🟢 CORREÇÃO 1: Deixa o modal mais largo, ocupando a tela toda
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24), 
      
      title: Column(
        children: [
          const Text("Avaliação da Partida", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _compareceu ? const Color(0xFF00E676).withAlpha(30) : Colors.redAccent.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _compareceu ? const Color(0xFF00E676) : Colors.redAccent),
            ),
            child: Text(
              _compareceu ? "Pontuação: $pontuacaoTotal / 50 pts (${notaEquivalenteStars.toStringAsFixed(1)}★)" : "W.O. DETECTADO",
              style: TextStyle(color: _compareceu ? const Color(0xFF00E676) : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 🟢 CORREÇÃO 2: Expanded envolve os textos para não quebrar a tela
                const Expanded(
                  child: Text("Compareceu ao jogo?", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                _buildSimNaoToggle(_compareceu, (val) => setState(() => _compareceu = val)),
              ],
            ),
            const SizedBox(height: 16),

            if (!_compareceu) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withAlpha(50)),
                ),
                child: const Text(
                  "Se o goleiro não compareceu, o pagamento não será liberado e o jogo entrará em contestação.",
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🟢 CORREÇÃO 2
                  const Expanded(
                    child: Text("Chegou no horário?", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  _buildSimNaoToggle(_noHorario, (val) => setState(() => _noHorario = val)),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🟢 CORREÇÃO 2
                  const Expanded(
                    child: Text("Personalidade", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  _buildStarPicker(_estrelasPersonalidade, (val) => setState(() => _estrelasPersonalidade = val)),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 🟢 CORREÇÃO 2
                  const Expanded(
                    child: Text("Nível Técnico", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  _buildStarPicker(_estrelasTecnica, (val) => setState(() => _estrelasTecnica = val)),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _comentarioController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Escreva sua experiência (opcional)...",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],

            if (_enviando)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
        ),
        if (!_compareceu)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _enviando
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onContestarWO();
                  },
            child: const Text("CONTESTAR W.O.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: _enviando ? null : () => _salvarAvaliacao(notaEquivalenteStars, pontuacaoTotal),
            child: const Text("CONFIRMAR E PAGAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}