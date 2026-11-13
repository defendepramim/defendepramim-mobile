class Dinheiro {
  /// Converte um valor em Reais (double) para Centavos (int) para enviar ao servidor
  static int paraCentavos(double valorReal) {
    return (valorReal * 100).round();
  }

  /// Converte Centavos (int) vindos do servidor para Reais (double) para a UI
  static double paraReal(int centavos) {
    return centavos / 100.0;
  }

  /// Formata Centavos diretamente para texto (ex: "37,50")
  static String formatar(int centavos) {
    return paraReal(centavos).toStringAsFixed(2).replaceAll('.', ',');
  }
}