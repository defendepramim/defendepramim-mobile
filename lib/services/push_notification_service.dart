import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:defendepramim/ui/screens/tela_chat_jogo.dart'; 
import 'package:defendepramim/ui/screens/home_goleiro.dart'; 
import 'package:defendepramim/ui/screens/home_contratante.dart';

class PushNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // 🟢 TRAVA NOVA: Garante que o push inicial só te puxe 1 vez por sessão!
  static bool _initialMessageProcessada = false;
  static bool _processandoNavegacao = false;

  Future<void> inicializar() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('🔔 Permissão para notificações concedida!');

      String? token = await _fcm.getToken();
      debugPrint("📱 FCM Token: $token");

      if (token != null) {
        await _salvarTokenNoBanco(token);
      }

      _fcm.onTokenRefresh.listen(_salvarTokenNoBanco);

      // CASO 1: Com o app ABERTO (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📩 Notificação recebida com o app aberto: ${message.notification?.title}');
      });

      // CASO 2: Clicou na notificação com o app em BACKGROUND
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🎯 O utilizador clicou na notificação em background!');
        _tratarNavegacao(message);
      });

      // CASO 3: App estava FECHADO e foi aberto pela notificação
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        // 🟢 AQUI ESTÁ A MÁGICA: Só entra se não tiver processado ainda!
        if (message != null && !_initialMessageProcessada) {
          _initialMessageProcessada = true; 
          debugPrint('🚀 O app foi iniciado a partir de uma notificação!');
          _tratarNavegacao(message);
        }
      });

    } else {
      debugPrint('🔕 Utilizador negou as notificações.');
    }
  }

  Future<void> _tratarNavegacao(RemoteMessage message) async {
    if (_processandoNavegacao) return; 
    _processandoNavegacao = true;

    final tipo = message.data['tipo'];
    final idJogo = message.data['idJogo'];

    debugPrint("🎯 Notificação clicada -> Tipo: $tipo | idJogo: $idJogo");

    if (tipo == 'chat_jogo') {
      if (idJogo == null) {
        _processandoNavegacao = false;
        return;
      }

      try {
        final jogoDoc = await FirebaseFirestore.instance.collection('jogos').doc(idJogo).get();
        if (!jogoDoc.exists) {
          _processandoNavegacao = false;
          return;
        }

        final jogo = jogoDoc.data()!;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        
        String nomeDestinatario = "Usuário";
        if (jogo['idContratante'] == uid) {
          nomeDestinatario = jogo['nomeGoleiro'] ?? "Goleiro";
        } else {
          nomeDestinatario = "Contratante"; 
        }

        final dataHora = (jogo['dataHora'] as Timestamp).toDate();
        final duracao = (jogo['duracao'] as num?)?.toInt() ?? 60;

        navigatorKey.currentState?.popUntil((route) => route.isFirst);
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => TelaChatJogo(
              idJogo: idJogo,
              nomeDestinatario: nomeDestinatario,
              dataHoraJogo: dataHora,
              duracaoJogo: duracao,
            ),
          ),
        );
      } catch (e) {
        debugPrint("Erro ao tentar abrir o chat pela notificação: $e");
      }
    }

    if (tipo == 'nova_pelada') {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomeGoleiro(indiceInicial: 1),
        ),
        (route) => false, 
      );
    }

    if (tipo == 'aceitou_jogo' || tipo == 'goleiro_desistiu') {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeContratante(indiceInicial: 0)),
        (route) => false, 
      );
    }

    await Future.delayed(const Duration(seconds: 1));
    _processandoNavegacao = false;
  }

  Future<void> _salvarTokenNoBanco(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
          'fcmToken': token,
          }, SetOptions(merge: true)
        );
        debugPrint('✅ Token FCM atualizado no Firestore.');

        final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
        final tipoPerfil = doc.data()?['tipoPerfil']; 

        if (tipoPerfil == 'goleiro') {
          await _fcm.subscribeToTopic('goleiros_ativos');
          debugPrint('📻 Goleiro sintonizado no tópico: goleiros_ativos');
        } else {
          await _fcm.unsubscribeFromTopic('goleiros_ativos');
        }
      } catch (e) {
        debugPrint('❌ Erro no fluxo do Token/Tópico: $e');
      }
    }
  }
}