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
  final TextInputAction? textInputAction; // Melhoria de UX
  final Function(String)? onChanged; // Para validação dinâmica

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
  });

  @override
  Widget build(BuildContext context) {
    // Pegando a cor primária do tema para não ficar "hardcoded"
    final primaryColor = Theme.of(context).primaryColor;

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textInputAction: textInputAction,
      onChanged: onChanged,
      
      // Estilo do texto digitado
      style: const TextStyle(fontSize: 16),

      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        suffixIcon: suffixIcon,
        
        // Espaçamento interno
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),

        // Borda padrão
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),

        // Borda quando clicado (Foco)
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),

        // Borda de erro
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        
        // Label flutuante quando focado
        floatingLabelStyle: TextStyle(color: primaryColor),
      ),
    );
  }
}