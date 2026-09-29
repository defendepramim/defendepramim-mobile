import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ModalCadastroPix extends StatefulWidget {
  const ModalCadastroPix({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModalCadastroPix(),
    );
  }

  @override
  State<ModalCadastroPix> createState() => _ModalCadastroPixState();
}

class _ModalCadastroPixState extends State<ModalCadastroPix> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cPix = TextEditingController();
  final TextEditingController _cConfirmaPix = TextEditingController();
  
  String _tipoPixSelecionado = "CPF";
  final List<String> _tiposPix = ["CPF", "Telefone", "E-mail", "Chave Aleatória"];
  bool _salvando = false;

  @override
  void dispose() {
    _cPix.dispose();
    _cConfirmaPix.dispose();
    super.dispose();
  }

  Future<void> _salvarChaveNoFirebase() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      if (uid != null) {
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
          'chavePix': _cPix.text.trim(),
          'tipoPix': _tipoPixSelecionado,
        });

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Chave Pix cadastrada com sucesso!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao salvar: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey, // 🟢 Proteção dupla ativa
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "CONFIGURAR RECEBIMENTO",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                "Insira seus dados Pix corretamente. Chaves digitadas incorretamente impossibilitam a transferência do seu saldo.",
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Seletor do Tipo de Pix
              const Text("Tipo de Chave", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _tipoPixSelecionado,
                    dropdownColor: const Color(0xFF1E1E1E),
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    items: _tiposPix.map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                    onChanged: (novoValor) {
                      if (novoValor != null) setState(() => _tipoPixSelecionado = novoValor);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campo 1: Chave Pix
              TextFormField(
                controller: _cPix,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Digite sua chave Pix",
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  prefixIcon: const Icon(Icons.pix, color: Color(0xFF00E676), size: 18),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? "Insira a chave Pix" : null,
              ),
              const SizedBox(height: 12),

              // Campo 2: Confirmação da Chave Pix
              TextFormField(
                controller: _cConfirmaPix,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Confirme sua chave Pix",
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFF666666), size: 18),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                // 🟢 SEGUNDA BARREIRA DE PROTEÇÃO
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return "Confirme a chave Pix";
                  if (val.trim() != _cPix.text.trim()) return "As chaves Pix digitadas não conferem!";
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // 🟢 CORRIGIDO: De Sxl para SizedBox normal
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _salvando ? null : _salvarChaveNoFirebase,
                  child: _salvando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text("SALVAR CHAVE DE RECEBIMENTO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}