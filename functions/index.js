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
            topic: "goleiros_ativos", // O app deve assinar esse tópico
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

            if (alvo !== "todos") {
                query = query.where("tipoPerfil", "==", alvo);
            }

            const usuariosSnapshot = await query.get();
            const tokens = [];

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

            const payload = {
                notification: { title: titulo, body: mensagem },
                tokens: tokens,
            };

            const response = await admin.messaging().sendMulticast(payload);
            
            console.log(`Aviso do Admin disparado! Sucessos: ${response.successCount}, Falhas: ${response.failureCount}`);

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
// 4. 🤖 ROBÔ DE PAGAMENTO AUTOMÁTICO BLINDADO (Roda a cada 1 hora)
// ============================================================================
exports.rotinaPagamentoAutomatico = functions.pubsub.schedule('every 1 hours').onRun(async (context) => {
    const db = admin.firestore();
    const agora = admin.firestore.Timestamp.now();
  
    // 1. Busca todos os jogos que ainda estão travados em 'fechado'
    const jogosSnapshot = await db.collection('jogos').where('status', '==', 'fechado').get();
  
    if (jogosSnapshot.empty) {
      console.log("Nenhum jogo pendente de pagamento automático.");
      return null;
    }
  
    let promessasTransacao = [];
  
    // 2. Varre jogo por jogo
    jogosSnapshot.forEach((doc) => {
      const dados = doc.data();
      if (!dados.dataHora || !dados.idGoleiro) return;
  
      const dataHoraJogo = dados.dataHora.toDate();
      const duracaoMin = dados.duracao || 60;
  
      // Calcula o limite: Fim da partida + 12 horas (Pode ajustar o 12 se quiser)
      const limitePagamento = new Date(dataHoraJogo.getTime() + (duracaoMin * 60000) + (12 * 3600000));
  
      // Se a hora atual já passou do limite das 12h após o fim do jogo, paga o goleiro!
      if (agora.toDate() > limitePagamento) {
        const idJogo = doc.id;
        const idGoleiro = dados.idGoleiro;
        const valorRepasse = dados.valorGoleiro || dados.valor || 0.0;
  
        const jogoRef = db.collection('jogos').doc(idJogo);
        const goleiroRef = db.collection('usuarios').doc(idGoleiro);
        const extratoGoleiro = goleiroRef.collection('extrato').doc();
        const transacaoGeralRef = db.collection('transacoes').doc();
  
        // 3. Executa a transação segura direto no servidor
        const operacao = db.runTransaction(async (transaction) => {
          const jSnap = await transaction.get(jogoRef);
          
          // 🛡️ Trava de segurança máxima: Se o status mudou 1 segundo atrás, aborta.
          if (jSnap.data().status !== 'fechado') return;
  
          // Atualiza Jogo
          transaction.update(jogoRef, {
            status: 'finalizado',
            pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            finalizadoAutomaticamente: true
          });
  
          // Atualiza Saldo do Goleiro e contador de partidas
          transaction.update(goleiroRef, {
            saldo: admin.firestore.FieldValue.increment(valorRepasse),
            atuadas: admin.firestore.FieldValue.increment(1)
          });
  
          // Gera o extrato na sub-coleção do goleiro (Como estava no seu mobile)
          transaction.set(extratoGoleiro, {
            id: extratoGoleiro.id,
            tipo: 'recebimento',
            valor: valorRepasse,
            data: admin.firestore.FieldValue.serverTimestamp(),
            descricao: `Pelada (Auto): ${dados.local || 'Arena'}`,
            idJogo: idJogo,
            status: 'concluido'
          });

          // Registra a transação global para histórico administrativo
          transaction.set(transacaoGeralRef, {
            idUsuario: idGoleiro,
            tipo: "recebimento",
            valor: valorRepasse,
            status: "concluido",
            descricao: `Pagamento pela partida (${dados.local || 'Local não informado'})`,
            data: admin.firestore.FieldValue.serverTimestamp(),
            idJogo: idJogo,
          });
        });
  
        promessasTransacao.push(operacao);
      }
    });
  
    // Aguarda todos os pagamentos dessa "leva" terminarem
    await Promise.all(promessasTransacao);
    console.log(`Sucesso: ${promessasTransacao.length} goleiros foram pagos automaticamente neste ciclo!`);
    
    return null;
  });

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