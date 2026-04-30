import 'package:cloud_firestore/cloud_firestore.dart';

class ServerTime {
  /// Obtém a hora atual confiável.
  /// No futuro, você pode trocar por uma chamada de API, 
  /// mas por enquanto usaremos o DateTime do dispositivo com toUtc.
  static Future<DateTime> agoraUtc() async {
    // Simulando um delay de rede para o app se comportar como se estivesse consultando algo
    await Future.delayed(const Duration(milliseconds: 200));
    return DateTime.now().toUtc();
  }
}