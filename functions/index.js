const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Inicializa o Firebase no servidor
admin.initializeApp();

// ============================================================================
// 1. AVISAR GOLEIROS SOBRE NOVA PELADA (Disparo em Massa para um Tópico)
// ============================================================================
exports.notificarNovaPelada = functions.firestore
    .document("jogos/{jogoId}")
    .onCreate(async (snap, context) => {
        const jogo = snap.data();

        // Monta a notificação
        const mensagem = {
            topic: "goleiros_ativos", // Vamos fazer o app assinar esse tópico depois!
            notification: {
                title: "⚽ Nova Convocação Aberta!",
                body: `Pelada de R$ ${jogo.valor.toFixed(2)} dia ${jogo.dataExibicao} às ${jogo.horaExibicao}. Aceite rápido!`,
            },
        };

        try {
            await admin.messaging().send(mensagem);
            console.log("Notificação disparada para todos os goleiros!");
        } catch (error) {
            console.error("Erro ao enviar notificação de nova pelada:", error);
        }
    });

// ============================================================================
// 2. AVISAR MUDANÇAS DE STATUS (Cancelado pelo Contratante ou Aceito pelo Goleiro)
// ============================================================================
exports.notificarMudancaStatus = functions.firestore
    .document("jogos/{jogoId}")
    .onUpdate(async (change, context) => {
        const jogoAntes = change.before.data();
        const jogoDepois = change.after.data();

        // Se o status não mudou (ex: editou só o local), interrompe a função
        if (jogoAntes.status === jogoDepois.status) return null;

        // 🔴 CASO A: Contratante cancelou e já tinha um Goleiro escalado
        if (jogoDepois.status === "cancelado" && jogoDepois.idGoleiro) {
            const goleiroDoc = await admin.firestore().collection("usuarios").doc(jogoDepois.idGoleiro).get();
            const tokenGoleiro = goleiroDoc.data()?.fcmToken;

            if (tokenGoleiro) {
                await admin.messaging().send({
                    token: tokenGoleiro,
                    notification: {
                        title: "🚨 Jogo Cancelado",
                        body: `O contratante cancelou a pelada do dia ${jogoDepois.dataExibicao}.`,
                    }
                });
            }
        }

        // 🟢 CASO B: Goleiro Aceitou a Pelada
        if (jogoDepois.status === "fechado" && jogoAntes.status === "aberto") {
            const contratanteDoc = await admin.firestore().collection("usuarios").doc(jogoDepois.idContratante).get();
            const tokenContratante = contratanteDoc.data()?.fcmToken;

            if (tokenContratante) {
                await admin.messaging().send({
                    token: tokenContratante,
                    notification: {
                        title: "🧤 Habemus Goleiro!",
                        body: `Um goleiro acabou de aceitar sua convocação para o dia ${jogoDepois.dataExibicao}!`,
                    }
                });
            }
        }

        return null;
    });

// ============================================================================
// 3. DISPARO EM MASSA PELO PAINEL ADMIN (Central de Notificações)
// ============================================================================
exports.dispararNotificacaoAdmin = functions.firestore
    .document("notificacoes/{docId}")
    .onCreate(async (snap, context) => {
        const dados = snap.data();
        const titulo = dados.titulo;
        const mensagem = dados.mensagem;
        const alvo = dados.publicoAlvo; // 'todos', 'goleiro', 'contratante'

        try {
            let query = admin.firestore().collection("usuarios");

            // Se o alvo não for 'todos', filtra pelo tipo de perfil
            if (alvo !== "todos") {
                query = query.where("tipoPerfil", "==", alvo);
            }

            const usuariosSnapshot = await query.get();
            const tokens = [];

            // Vasculha os usuários e coleta os tokens válidos
            usuariosSnapshot.forEach((doc) => {
                const fcmToken = doc.data().fcmToken;
                if (fcmToken) {
                    tokens.push(fcmToken);
                }
            });

            if (tokens.length === 0) {
                console.log("Nenhum token encontrado para o público alvo.");
                return snap.ref.update({ status: "sem_destinatarios" });
            }

            // Monta o pacote Multicast (Disparo em lote)
            const payload = {
                notification: {
                    title: titulo,
                    body: mensagem,
                },
                tokens: tokens, // Array com todos os tokens que vão apitar
            };

            // Dispara para geral de uma vez (Firebase cuida da entrega)
            const response = await admin.messaging().sendMulticast(payload);
            
            console.log(`Aviso do Admin disparado! Sucessos: ${response.successCount}, Falhas: ${response.failureCount}`);

            // Atualiza o card no painel do Admin avisando que deu certo
            return snap.ref.update({ 
                status: "concluido",
                sucessos: response.successCount,
                falhas: response.failureCount,
                dataProcessamento: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (error) {
            console.error("Erro fatal ao disparar notificação do admin:", error);
            return snap.ref.update({ status: "erro_no_envio", erro: error.message });
        }
    });

// ============================================================================
// 4. ROTINA DE PAGAMENTO AUTOMÁTICO E FINALIZAÇÃO DE JOGOS (Roda a cada 30 min)
// ============================================================================
exports.rotinaPagamentoAutomatico = functions.pubsub.schedule('every 30 minutes').onRun(async (context) => {
    try {
        const db = admin.firestore();
        const agora = new Date();

        // 1. Busca a variável global configurada pelo Admin
        const configSnapshot = await db.collection('configuracoes').doc('global').get();
        let horasPagamentoAuto = 12; // Valor padrão de segurança

        if (configSnapshot.exists && configSnapshot.data().horasPagamentoAuto !== undefined) {
            horasPagamentoAuto = configSnapshot.data().horasPagamentoAuto;
        }

        // Calcula o limite de tempo para liberação do pagamento
        const tempoLimiteDeCorte = new Date(agora);
        tempoLimiteDeCorte.setHours(tempoLimiteDeCorte.getHours() - horasPagamentoAuto);

        // 2. Busca jogos que estão 'fechados', e a dataHora é ANTES do limite de corte
        const snapshotJogos = await db.collection('jogos')
            .where('status', '==', 'fechado')
            .where('dataHora', '<', tempoLimiteDeCorte)
            .get();

        if (snapshotJogos.empty) {
            console.log(`Rotina OK: Nenhum jogo pendente de repasse (Regra: ${horasPagamentoAuto}h).`);
            return null;
        }

        console.log(`Iniciando repasse automático para ${snapshotJogos.size} jogos... (Regra: ${horasPagamentoAuto}h)`);

        // 3. Processa cada jogo encontrado
        for (const doc of snapshotJogos.docs) {
            const jogo = doc.data();
            const idJogo = doc.id;
            const valorRepasse = jogo.valorGoleiro || 0; // O que o goleiro tem a receber
            const idGoleiro = jogo.idGoleiro;

            if (valorRepasse > 0 && idGoleiro) {
                // Inicia uma transaction para garantir a integridade dos dados
                await db.runTransaction(async (t) => {
                    const jogoRef = db.collection('jogos').doc(idJogo);
                    const goleiroRef = db.collection('usuarios').doc(idGoleiro);
                    
                    // A. Atualiza o status do jogo e crava a flag para o app Mobile ler
                    t.update(jogoRef, {
                        status: 'finalizado',
                        finalizadoAutomaticamente: true,
                        notificadoNoApp: false // O mobile vai ver isso e exibir o alerta
                    });

                    // B. Adiciona o saldo na carteira do Goleiro
                    t.update(goleiroRef, {
                        saldo: admin.firestore.FieldValue.increment(valorRepasse)
                    });

                    // C. Registra a transação global para histórico
                    const novaTransacaoRef = db.collection('transacoes').doc();
                    t.set(novaTransacaoRef, {
                        idUsuario: idGoleiro,
                        tipo: "recebimento",
                        valor: valorRepasse,
                        status: "concluido",
                        descricao: `Pagamento pela partida (${jogo.local || 'Local não informado'})`,
                        data: admin.firestore.FieldValue.serverTimestamp(),
                        idJogo: idJogo,
                    });
                });
                console.log(`[SUCESSO] Repasse de R$ ${valorRepasse} para o goleiro ${idGoleiro} (Jogo: ${idJogo})`);
            } else {
                console.warn(`[AVISO] Jogo ${idJogo} não pôde ser repassado. Sem goleiro ou valor zero.`);
            }
        }
        
        console.log("Lote de pagamentos finalizado com sucesso.");
        return null;

    } catch (error) {
        console.error("Erro fatal na rotina de pagamentos:", error);
        return null;
    }
});


// Apague tudo o que estava abaixo da linha "return null; \n });" da rotina de pagamentos e cole isso:

// ============================================================================
// 5. GATILHO REATIVO: CRIAR CONTA DE ADMINISTRADOR EXCLUSIVA PELO PAINEL
// ============================================================================
exports.gatilhoCriarNovoAdmin = functions.firestore
  .document('solicitacoes_admin/{idSolicitacao}')
  .onCreate(async (snapshot, context) => {
    const dados = snapshot.data();
    
    // Evita rodar se não estiver pendente
    if (dados.status !== 'pendente') return null;
    
    const firestore = admin.firestore();
    const email = dados.email.trim().toLowerCase();
    const senha = dados.senha;
    const nome = dados.nome;

    try {
      console.log(`🚀 Criando conta Auth exclusiva para Admin: ${email}`);

      // 1️⃣ Cria no Firebase Authentication com a senha digitada no painel
      const userRecord = await admin.auth().createUser({
        email: email,
        password: senha,
        displayName: nome,
      });

      const uid = userRecord.uid;

      // 2️⃣ Salva na coleção geral 'usuarios' com isAdmin: true
      await firestore.collection('usuarios').doc(uid).set({
        email: email,
        nome: nome,
        isAdmin: true,
        criadoEm: admin.firestore.FieldValue.serverTimestamp()
      });

      // 3️⃣ Salva na coleção de listagem 'administradores'
      await firestore.collection('administradores').doc(uid).set({
        email: email,
        nome: nome,
        isAdmin: true,
        criadoEm: admin.firestore.FieldValue.serverTimestamp()
      });

      // 4️⃣ Limpa a senha do documento temporário por segurança e marca como concluído
      await snapshot.ref.update({
        status: 'concluido',
        uidGerado: uid,
        senha: '[PROTEGIDA E APAGADA]'
      });

      console.log(`🏆 Admin ${email} criado com sucesso!`);
      return null;

    } catch (error) {
      console.error(`🔴 Erro ao criar admin no gatilho:`, error);
      // Registra o erro no doc para você ver no painel se algo falhar (ex: e-mail duplicado)
      await snapshot.ref.update({
        status: 'erro',
        erroMensagem: error.message
      });
      return null;
    }
  });