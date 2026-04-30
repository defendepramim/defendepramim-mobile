import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_provider.dart';
import 'home_goleiro.dart';
import 'home_contratante.dart';
import 'cadastro_screen.dart'; // Certifique-se de que o import da sua tela de cadastro está correto
import 'initial_screen.dart'; 

class AuthCheck extends ConsumerWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Observa o estado de login (Firebase Auth)
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        // 🚪 Se não há usuário logado, vai para a tela de boas-vindas/login
        if (user == null) return const InitialScreen();

        // 🔍 Se está logado, vamos observar o PERFIL no Firestore (Stream)
        final perfilAsync = ref.watch(userProfileProvider);

        return perfilAsync.when(
          data: (perfil) {
            // 📝 CASO 1: O usuário existe no Auth, mas NÃO tem documento no Firestore
            // Isso acontece se ele fechou o app no meio do cadastro.
            if (perfil == null) {
              return const TelaCadastro(); 
            }

            // ⚡ CASO 2: Perfil encontrado! Direciona para a Home correta.
            // Usei .toLowerCase() para evitar erros de digitação (Ex: 'Goleiro' vs 'goleiro')
            if (perfil.tipoPerfil.toLowerCase() == 'goleiro') {
              return const HomeGoleiro();
            } else {
              return const HomeContratante();
            }
          },
          // ⏳ Enquanto o Firestore busca os dados (milissegundos iniciais)
          loading: () => const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            ),
          ),
          // ⚠️ Erro ao acessar o Firestore
          error: (e, _) => Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                "Erro ao carregar perfil: $e",
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        );
      },
      // ⏳ Enquanto o Firebase Auth está inicializando
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
      ),
      // ⚠️ Erro na autenticação
      error: (e, _) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text("Erro de Autenticação: $e", style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }
}