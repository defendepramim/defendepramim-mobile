import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ModalCadastroPix extends StatefulWidget {
  const ModalCadastroPix({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que o modal suba com o teclado
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: const ModalCadastroPix(),
      ),
    );
  }

  @override
  State<ModalCadastroPix> createState() => _ModalCadastroPixState();
}

class _ModalCadastroPixState extends State<ModalCadastroPix> {
  String _tipoSelecionado = 'cpf';
  final TextEditingController _chaveController = TextEditingController();
  bool _processando = false;

  final Map<String, String> _tiposPix = {
    'cpf': 'CPF / CNPJ',
    'telefone': 'Telefone',
    'email': 'E-mail',
    'aleatoria': 'Chave Aleatória',
  };

  Future<void> _salvarPix() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final chave = _chaveController.text.trim();

    if (uid == null) return;

    if (chave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Digite a sua chave PIX!"), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _processando = true);

    try {
      // Atualiza o documento do goleiro com os novos campos
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'tipoPix': _tipoSelecionado,
        'chavePix': chave,
      });

      if (mounted) {
        Navigator.pop(context); // Fecha o modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chave PIX salva! Saque liberado. 💸"), backgroundColor: Color(0xFF00E676)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao salvar: $e"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00E676);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "CADASTRAR PIX",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 20),
          const Text("TIPO DE CHAVE", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          
          // Chips de seleção do Tipo de Chave
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tiposPix.entries.map((entry) {
              final isSelected = _tipoSelecionado == entry.key;
              return ChoiceChip(
                label: Text(entry.value),
                selected: isSelected,
                selectedColor: primaryColor.withOpacity(0.2),
                backgroundColor: Colors.white.withOpacity(0.05),
                labelStyle: TextStyle(
                  color: isSelected ? primaryColor : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(color: isSelected ? primaryColor : Colors.transparent),
                onSelected: (selected) {
                  if (selected) setState(() => _tipoSelecionado = entry.key);
                },
              );
            }).toList(),
          ),
          
          const SizedBox(height: 20),
          const Text("SUA CHAVE", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          
          // Campo de digitação
          TextField(
            controller: _chaveController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            keyboardType: _tipoSelecionado == 'email' 
                ? TextInputType.emailAddress 
                : (_tipoSelecionado == 'telefone' || _tipoSelecionado == 'cpf' ? TextInputType.number : TextInputType.text),
            decoration: InputDecoration(
              hintText: "Digite a chave selecionada...",
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Botão Salvar
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _processando ? null : _salvarPix,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _processando
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("SALVAR CHAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}