import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CampoInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;

  const CampoInput({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    // Cores estáticas em Hexadecimal (Evita cálculos de opacidade em tempo de execução)
    const neonGreen = Color(0xFF00E676);
    const darkInputBg = Color(0x0DFFFFFF); // Equivalente a Colors.white.withOpacity(0.05)
    const borderColor = Color(0x1AFFFFFF); // Equivalente a Colors.white10

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      
      // ✨ PROTEÇÃO DE PERFORMANCE DO TECLADO: 
      // Se for senha, desliga o corretor ortográfico e as sugestões do teclado.
      // Isso tira um peso gigantesco do processador do celular na hora de digitar!
      autocorrect: !obscure,
      enableSuggestions: !obscure,
      
      style: const TextStyle(fontSize: 16, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        suffixIcon: suffixIcon,
        
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColor),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neonGreen, width: 2),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        
        floatingLabelStyle: const TextStyle(color: neonGreen),
        filled: true,
        fillColor: darkInputBg,
      ),
    );
  }
}