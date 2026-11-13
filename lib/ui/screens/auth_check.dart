import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_provider.dart';
import 'home_goleiro.dart';
import 'home_contratante.dart';
import 'cadastro_screen.dart'; 
import 'initial_screen.dart'; 

class AuthCheck extends ConsumerWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Observa o estado de login (Firebase Auth)
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        // 🚪 Se não há usuário logado, vai para a tela inicial
        if (user == null) return const InitialScreen();

        // 🚀 BLINDAGEM MÁXIMA: Lemos direto da base de dados (Stream) sem intermediários!
        // Isto ignora qualquer valor por defeito que os Models do Riverpod possam estar a aplicar.
        return StreamBuilder(
          stream: FirebaseFirestore.instance.collection('usuarios').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
              );
            }

            final doc = snapshot.data;
            
            // O documento ainda nem existe
            if (doc == null || !doc.exists) {
              return TelaCadastro(googleUser: user); 
            }

            final dados = doc.data() as Map?;
            if (dados == null) return TelaCadastro(googleUser: user);

            // Verificamos exatamente o que está guardado no Firestore
            final temCpf = dados['cpf'] != null && dados['cpf'].toString().trim().isNotEmpty;
            final tipoPerfil = (dados['tipoPerfil'] ?? '').toString().trim().toLowerCase();
            final temTelefone = dados['telefone'] != null && dados['telefone'].toString().trim().isNotEmpty;

            // Se o servidor só criou a base da carteira e faltam os dados vitais:
            if (!temCpf || tipoPerfil.isEmpty || !temTelefone) {
              return TelaCadastro(googleUser: user);
            }

            // Tudo preenchido de verdade! Roteamento final:
            if (tipoPerfil == 'goleiro') {
              return const HomeGoleiro();
            } else {
              return const HomeContratante();
            }
          },
        );
      },
      loading: () => const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))),
      error: (e, _) => Scaffold(backgroundColor: Colors.black, body: Center(child: Text("Erro: $e", style: const TextStyle(color: Colors.redAccent)))),
    );
  }
}