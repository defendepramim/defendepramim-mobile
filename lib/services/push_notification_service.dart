import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> inicializar() async {
    // 1. Pede permissão para o utilizador
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('🔔 Permissão para notificações concedida!');

      // 2. Pega o Token único do aparelho
      String? token = await _fcm.getToken();
      debugPrint("📱 FCM Token: $token");

      if (token != null) {
        await _salvarTokenNoBanco(token);
      }

      // Atualiza caso o token mude
      _fcm.onTokenRefresh.listen(_salvarTokenNoBanco);

      // ========================================================================
      // ✨ CONFIGURAÇÃO DE RECEBIMENTO DE MENSAGENS ✨
      // ========================================================================

      // CASO 1: Com o app ABERTO (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📩 Notificação recebida com o app aberto: ${message.notification?.title}');
        // Aqui, opcionalmente, podes disparar um SnackBar ou Alerta customizado na tela
      });

      // CASO 2: Clicou na notificação com o app em BACKGROUND
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🎯 O utilizador clicou na notificação em background!');
        // Aqui podes fazer um Navigator para abrir direto na aba de jogos, por exemplo
      });

    } else {
      debugPrint('🔕 Utilizador negou as notificações.');
    }
  }

  // --- FUNÇÃO INTERNA PARA SALVAR NO FIRESTORE E ASSINAR TÓPICO ---
  Future<void> _salvarTokenNoBanco(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    if (uid != null) {
      try {
        // Guarda no Firestore do Usuário
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
          'fcmToken': token,
        });
        debugPrint('✅ Token FCM atualizado no Firestore.');

        // Busca o tipoPerfil para saber se assina o canal das peladas
        final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
        final tipoPerfil = doc.data()?['tipoPerfil']; 

        if (tipoPerfil == 'goleiro') {
          // Goleiro assina o tópico para receber "Nova Pelada Aberta"
          await _fcm.subscribeToTopic('goleiros_ativos');
          debugPrint('📻 Goleiro sintonizado no tópico: goleiros_ativos');
        } else {
          // Se for contratante e por acaso estava no tópico, desassina
          await _fcm.unsubscribeFromTopic('goleiros_ativos');
        }

      } catch (e) {
        debugPrint('❌ Erro no fluxo do Token/Tópico: $e');
      }
    }
  }
}