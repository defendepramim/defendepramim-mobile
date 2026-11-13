import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/notificacao_model.dart'; // 🟢 CONFIRME SE O CAMINHO ESTÁ CERTO NO SEU PC
import '../../services/notificacao_service.dart';

class BotaoNotificacao extends StatelessWidget {
  const BotaoNotificacao({super.key});

  final Color primaryColor = const Color(0xFF00E676);
  final Color surfaceColor = const Color(0xFF1E1E1E);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox(); 

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notificacoes')
          .where('idUsuario', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        
        List<NotificacaoModel> notificacoes = [];
        if (snapshot.hasData) {
          notificacoes = snapshot.data!.docs
              .map((doc) => NotificacaoModel.fromFirestore(doc))
              .toList();
        }

        // Verifica se tem pelo menos UMA notificação que não foi lida
        final bool temNaoLida = notificacoes.any((n) => n.lida == false);

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
              onPressed: () => _abrirNotificacoes(context, user.uid), // 🟢 Passamos só o UID agora!
            ),
            
            if (temNaoLida)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                ),
              )
          ],
        );
      },
    );
  }

  // --- 🚀 NOVA FUNÇÃO: MARCAR TODAS COMO LIDAS EM MASSA ---
  Future<void> _marcarTodasComoLidas(String uid) async {
    final db = FirebaseFirestore.instance;
    // Busca só as que ainda não foram lidas para economizar leitura no Firebase
    final unreadSnap = await db.collection('notificacoes')
        .where('idUsuario', isEqualTo: uid)
        .where('lida', isEqualTo: false)
        .get();

    if (unreadSnap.docs.isEmpty) return;

    // O 'batch' agrupa várias alterações e manda pro servidor de uma vez só!
    final batch = db.batch();
    for (var doc in unreadSnap.docs) {
      batch.update(doc.reference, {'lida': true});
    }
    await batch.commit();
  }

  // --- 🔔 CENTRAL DE NOTIFICAÇÕES (UI) ---
  void _abrirNotificacoes(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          // 🟢 AGORA O MODAL TEM O PRÓPRIO STREAM BUILDER PARA ATUALIZAR AO VIVO!
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notificacoes')
                .where('idUsuario', isEqualTo: uid)
                .snapshots(),
            builder: (context, snapshot) {
              
              List<NotificacaoModel> notificacoes = [];
              if (snapshot.hasData) {
                notificacoes = snapshot.data!.docs
                    .map((doc) => NotificacaoModel.fromFirestore(doc))
                    .toList();
                notificacoes.sort((a, b) => b.data.compareTo(a.data));
              }

              final bool temNaoLida = notificacoes.any((n) => !n.lida);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Notificações",
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            // 🟢 BOTÃO "LER TODAS" APARECE AQUI SE HOUVER NÃO LIDAS
                            if (temNaoLida)
                              TextButton(
                                onPressed: () => _marcarTodasComoLidas(uid),
                                child: Text("Ler Todas", style: TextStyle(color: primaryColor, fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  
                  Expanded(
                    child: notificacoes.isEmpty
                        ? const Center(
                            child: Text("Nenhuma notificação por enquanto.", 
                            style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: notificacoes.length,
                            itemBuilder: (context, index) {
                              final notif = notificacoes[index];
                              return _buildItemNotificacao(notif);
                            },
                          ),
                  ),
                ],
              );
            }
          ),
        );
      },
    );
  }

  // Componente visual que desenha a notificação baseada no Model
  Widget _buildItemNotificacao(NotificacaoModel notif) {
    IconData icone = Icons.notifications_active_outlined;
    Color corIcone = primaryColor;

    if (notif.tipo == 'cancelou_jogo') {
      icone = Icons.cancel_outlined;
      corIcone = Colors.redAccent;
    } else if (notif.tipo == 'aceitou_jogo') {
      icone = Icons.check_circle_outline;
      corIcone = primaryColor;
    } else if (notif.tipo == 'pagamento') {
      icone = Icons.attach_money;
      corIcone = Colors.orangeAccent;
    }

    final diferenca = DateTime.now().difference(notif.data);
    String dataTexto = "Agora mesmo";
    if (diferenca.inDays > 0) {
      dataTexto = "Há ${diferenca.inDays} dias";
    } else if (diferenca.inHours > 0) {
      dataTexto = "Há ${diferenca.inHours} horas";
    } else if (diferenca.inMinutes > 0) {
      dataTexto = "Há ${diferenca.inMinutes} minutos";
    }

    return Container(
      color: notif.lida ? Colors.transparent : Colors.white.withAlpha(13),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: corIcone.withAlpha(51),
          child: Icon(icone, color: corIcone),
        ),
        title: Text(
          notif.titulo, 
          style: TextStyle(color: Colors.white, fontWeight: notif.lida ? FontWeight.normal : FontWeight.bold)
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(notif.mensagem, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(dataTexto, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        trailing: notif.lida ? null : Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
        ),
        onTap: () {
          // 🟢 Clicou na individual? Ela atualiza na hora graças ao novo StreamBuilder!
          if (!notif.lida) {
            NotificacaoService().marcarComoLida(notif.id);
          }
        },
      ),
    );
  }
}