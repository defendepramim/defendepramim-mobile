const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Inicializa o Firebase no servidor
admin.initializeApp();

// ============================================================================
// 1. AVISAR GOLEIROS PRÓXIMOS SOBRE NOVA PELADA (Cirúrgico: Raio + Nível + Trava de Duplicidade)
// ============================================================================
exports.notificarNovaPelada = functions.firestore
    .document("jogos/{jogoId}")
    .onCreate(async (snap, context) => {
        const jogo = snap.data();
        const db = admin.firestore();

        // 🟢 TRAVA DE HORÁRIO (8h às 22h - Horário de Brasília)
        const agoraUtc = new Date();
        let horaBrasil = agoraUtc.getUTCHours() - 3;
        if (horaBrasil < 0) horaBrasil += 24;

        if (horaBrasil < 8 || horaBrasil >= 22) {
            console.log(`[SILENCIADO] Jogo ${snap.id} criado às ${horaBrasil}h. Goleiros não serão incomodados na madrugada.`);
            return null; 
        }

        const jogoLat = jogo.latitude || jogo.lat;
        const jogoLng = jogo.longitude || jogo.lng;

        if (!jogoLat || !jogoLng) {
            console.log(`Jogo ${snap.id} sem coordenadas, abortando disparo.`);
            return null;
        }

        // 🟢 DESCOBRIR QUAL O RANK EXIGIDO PELA PELADA
        const nivelExigidoStr = (jogo.nivelGoleiro || jogo.nivel || 'livre').toLowerCase();
        let rankExigido = 0; 
        
        if (nivelExigidoStr.includes('elite') || nivelExigidoStr.includes('pared')) {
            rankExigido = 2;
        } else if (nivelExigidoStr.includes('exp') || nivelExigidoStr.includes('inter') || nivelExigidoStr.includes('médio') || nivelExigidoStr.includes('medio')) {
            rankExigido = 1;
        }

        function calcularDistancia(lat1, lon1, lat2, lon2) {
            const R = 6371;
            const dLat = (lat2 - lat1) * Math.PI / 180;
            const dLon = (lon2 - lon1) * Math.PI / 180;
            const a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon/2) * Math.sin(dLon/2);
            return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)));
        }

        const hoje = new Date();
        hoje.setHours(0, 0, 0, 0);
        const inicioDoDia = admin.firestore.Timestamp.fromDate(hoje);
        const valorParaGoleiro = jogo.valorGoleiro || jogo.valor || 0.0;

        try {
            const goleirosSnap = await db.collection('usuarios').where('tipoPerfil', '==', 'goleiro').get();
            const batch = db.batch();
            let notificacoesGeradas = 0;
            
            // 🛡️ TRAVA CIRÚRGICA: Evita mandar 2 pushs pro mesmo celular físico
            const tokensCelularesProcessados = new Set();

            for (const doc of goleirosSnap.docs) {
                const goleiro = doc.data();

                if (!goleiro.lat || !goleiro.lng) continue;

                // 🛡️ Verifica se o aparelho já recebeu a notificação
                if (goleiro.fcmToken) {
                    if (tokensCelularesProcessados.has(goleiro.fcmToken)) continue;
                    tokensCelularesProcessados.add(goleiro.fcmToken);
                }

                const distancia = calcularDistancia(jogoLat, jogoLng, goleiro.lat, goleiro.lng);
                if (distancia > 10) continue;

                const nivelGoleiro = (goleiro.categoria || 'livre').toLowerCase();
                let rankGoleiro = 0;
                
                if (nivelGoleiro.includes('elite') || nivelGoleiro.includes('pared')) {
                    rankGoleiro = 2;
                } else if (nivelGoleiro.includes('exp') || nivelGoleiro.includes('inter') || nivelGoleiro.includes('médio') || nivelGoleiro.includes('medio')) {
                    rankGoleiro = 1;
                }

                if (rankGoleiro < rankExigido) continue; 

                // Anti-Spam (Máx 2 no dia do mesmo tipo)
                const recebidasHojeSnap = await db.collection('notificacoes').where('idUsuario', '==', doc.id).where('data', '>=', inicioDoDia).get();
                if (recebidasHojeSnap.docs.filter(d => d.data().tipo === 'nova_pelada').length >= 2) continue; 

                const dHora = jogo.dataHora ? jogo.dataHora.toDate() : new Date();
                const diaMes = jogo.dataExibicao || `${String(dHora.getDate()).padStart(2, '0')}/${String(dHora.getMonth() + 1).padStart(2, '0')}`;
                const horaStr = jogo.horaExibicao || `${String(dHora.getHours()).padStart(2, '0')}:${String(dHora.getMinutes()).padStart(2, '0')}`;

                const novaNotificacaoRef = db.collection('notificacoes').doc();
                batch.set(novaNotificacaoRef, {
                    idUsuario: doc.id,
                    titulo: "⚽ Nova Convocação na Área!",
                    mensagem: `Pelada de R$ ${valorParaGoleiro.toFixed(2)} dia ${diaMes} às ${horaStr} a apenas ${distancia.toFixed(1)}km de você!`,
                    tipo: "nova_pelada",
                    idJogo: context.params.jogoId,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp()
                });

                notificacoesGeradas++;
            }

            if (notificacoesGeradas > 0) await batch.commit();

        } catch (error) {
            console.error("Erro fatal ao processar envio:", error);
        }

        return null;
    });
    

// ============================================================================
// 2. 👁️ O OLHO DE SAURON: PUSH UNIVERSAL (Lê nossa nova coleção)
// ============================================================================
exports.dispararPushUniversal = functions.firestore
    .document("notificacoes/{docId}")
    .onCreate(async (snap, context) => {
        const notificacao = snap.data();
        const idUsuarioDestino = notificacao.idUsuario;

        if (!idUsuarioDestino) {
            console.log("Notificação sem idUsuarioDestino, ignorando.");
            return null;
        }

        try {
            // 1. Vai no banco buscar o Token (CPF do celular) daquele usuário
            const userDoc = await admin.firestore().collection("usuarios").doc(idUsuarioDestino).get();
            const token = userDoc.data()?.fcmToken;

            // Se o cara desinstalou o app ou não deu permissão, ele não tem token
            if (!token) {
                console.log(`Usuário ${idUsuarioDestino} não possui token FCM.`);
                return null;
            }

            // 2. Prepara o formato exato que a Apple/Google exigem
            const payload = {
                token: token,
                notification: {
                    title: notificacao.titulo,
                    body: notificacao.mensagem,
                },
                // Dados extras escondidos para o app ler quando o usuário clicar!
                data: {
                    tipo: notificacao.tipo || 'geral',
                    click_action: 'FLUTTER_NOTIFICATION_CLICK'
                }
            };

            // 🚀 A CORREÇÃO ESTÁ AQUI: Se a notificação tiver um idJogo, injeta ele no payload!
            if (notificacao.idJogo) {
                payload.data.idJogo = String(notificacao.idJogo);
            }

            // 3. Dispara o foguete! 🚀
            await admin.messaging().send(payload);
            console.log(`✅ Push Universal enviado com sucesso para ${idUsuarioDestino}`);
            return null;

        } catch (error) {
            console.error(`❌ Erro no Push Universal para ${idUsuarioDestino}:`, error);
            return null;
        }
    });


// ============================================================================
// 3. DISPARO EM MASSA PELO PAINEL ADMIN (Central de Notificações)
// ============================================================================
exports.dispararNotificacaoAdmin = functions.firestore
    .document("notificacoes/{docId}")
    .onCreate(async (snap, context) => {
        const dados = snap.data();
        const alvo = dados.publicoAlvo; // 'todos', 'goleiro', 'contratante'

        // 🛑 A TRAVA SALVADORA: Se não tem público alvo, NÃO é um disparo em massa.
        // É apenas um push comum (1 para 1). Então esse robô deve ignorar e voltar a dormir!
        if (!alvo) {
            return null;
        }

        const titulo = dados.titulo;
        const mensagem = dados.mensagem;

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

    // 🟢 2. BUSCA AS CONFIGURAÇÕES GLOBAIS ANTES DE PROCESSAR
    let taxaAppElite = 9.0;
    let taxaAppInter = 8.0;
    let taxaAppVarzea = 7.0;
    let horasPagamentoAuto = 12; // Valor padrão se falhar a leitura

    try {
        const configDoc = await db.collection('configuracoes').doc('global').get();
        if (configDoc.exists) {
            const conf = configDoc.data();
            taxaAppElite = conf.taxaAppElite ?? 9.0;
            taxaAppInter = conf.taxaAppInter ?? 8.0;
            taxaAppVarzea = conf.taxaAppVarzea ?? 7.0;
            horasPagamentoAuto = conf.horasPagamentoAuto ?? 12; // 🟢 Dinâmico via Admin
        }
    } catch (e) {
        console.error("Falha ao ler config global, usando taxas padrão:", e);
    }
  
    let promessasTransacao = [];
  
    // 3. Varre jogo por jogo
    jogosSnapshot.forEach((doc) => {
      const dados = doc.data();
      if (!dados.dataHora || !dados.idGoleiro) return;
  
      const dataHoraJogo = dados.dataHora.toDate();
      const duracaoMin = dados.duracao || 60;
  
      // 🟢 Limite: Fim da partida + Horas configuradas no Admin
      const msHorasAuto = horasPagamentoAuto * 3600000;
      const limitePagamento = new Date(dataHoraJogo.getTime() + (duracaoMin * 60000) + msHorasAuto);
  
      // Se a hora atual já passou do limite, paga o goleiro!
      if (agora.toDate() > limitePagamento) {
        const idJogo = doc.id;
        const idGoleiro = dados.idGoleiro;
        
        // 🟢 CÁLCULO DE SEGURANÇA (Respeita valorGoleiro ou calcula por nível)
        let valorRepasse = 0.0;
        
        if (dados.valorGoleiro) {
          valorRepasse = dados.valorGoleiro;
        } else {
          let nivel = (dados.nivelGoleiro || dados.nivel || '').toLowerCase();
          let taxaAplicar = taxaAppVarzea; // Padrão (Livre)
          
          if (nivel.includes('elite')) {
            taxaAplicar = taxaAppElite;
          } else if (nivel.includes('inter') || nivel.includes('experiente')) {
            taxaAplicar = taxaAppInter;
          }

          valorRepasse = Math.max(0, (dados.valor || 0) - taxaAplicar);
        }
  
        const jogoRef = db.collection('jogos').doc(idJogo);
        const goleiroRef = db.collection('usuarios').doc(idGoleiro);
        const extratoGoleiro = goleiroRef.collection('extrato').doc();
        const transacaoGeralRef = db.collection('transacoes').doc();
  
        // Executa a transação
        const operacao = db.runTransaction(async (transaction) => {
          const jSnap = await transaction.get(jogoRef);
          
          if (jSnap.data().status !== 'fechado') return;
  
          // Atualiza Jogo
          transaction.update(jogoRef, {
            status: 'finalizado',
            pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            finalizadoAutomaticamente: true,
            valorPagoAoGoleiro: valorRepasse // Salva para auditoria
          });

          // 🟢 Atualiza Saldo e Estatísticas do Goleiro
          transaction.update(goleiroRef, {
            saldo: admin.firestore.FieldValue.increment(valorRepasse),
            totalGanhos: admin.firestore.FieldValue.increment(valorRepasse),
            atuadas: admin.firestore.FieldValue.increment(1)
          });

          // 🟢 Atualiza as Estatísticas do Contratante
          if (dados.idContratante) {
            const contratanteRef = db.collection('usuarios').doc(dados.idContratante);
            transaction.update(contratanteRef, {
              jogosRealizados: admin.firestore.FieldValue.increment(1),
              partidasOrganizadas: admin.firestore.FieldValue.increment(1),
              totalGastos: admin.firestore.FieldValue.increment(dados.valor || 0)
            });
          }
  
          // Gera o extrato na sub-coleção do goleiro
          transaction.set(extratoGoleiro, {
            id: extratoGoleiro.id,
            tipo: 'recebimento',
            valor: valorRepasse,
            data: admin.firestore.FieldValue.serverTimestamp(),
            descricao: `Pelada (Auto): ${dados.local || 'Arena'}`,
            idJogo: idJogo,
            status: 'concluido'
          });

          // Registra a transação global
          transaction.set(transacaoGeralRef, {
            idUsuario: idGoleiro,
            tipo: "recebimento",
            valor: valorRepasse,
            status: "concluido",
            descricao: `Pagamento pela partida (${dados.local || 'Local não informado'})`,
            data: admin.firestore.FieldValue.serverTimestamp(),
            idJogo: idJogo,
          });

          // 🟢 GATILHO DA NOTIFICAÇÃO
          const nomeLocal = (dados.local || 'Arena').split('(')[0].trim();
          const valorFormatado = valorRepasse.toFixed(2).replace('.', ',');
          
          const diaJogo = String(dataHoraJogo.getDate()).padStart(2, '0');
          const mesJogo = String(dataHoraJogo.getMonth() + 1).padStart(2, '0');

          const pushRef = db.collection('notificacoes').doc();
          transaction.set(pushRef, {
            idUsuario: idGoleiro,
            titulo: "Pagamento Liberado! 💰",
            mensagem: `Boa defesa! R$ ${valorFormatado} do jogo em ${nomeLocal} (${diaJogo}/${mesJogo}) já estão na sua carteira.`,
            tipo: "pagamento",
            data: admin.firestore.FieldValue.serverTimestamp()
          });

        });
  
        promessasTransacao.push(operacao);
      }
    });
  
    await Promise.all(promessasTransacao);
    console.log(`Sucesso: ${promessasTransacao.length} goleiros pagos e notificados neste ciclo!`);
    
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


// ============================================================================
// 6. 🧹 GARI FINANCEIRO: ABATIMENTO AUTOMÁTICO DE MULTAS (BLINDADO COM TRANSACTION)
// ============================================================================
exports.abaterMultaAutomatica = functions.firestore
    .document("usuarios/{userId}")
    .onUpdate(async (change, context) => {
        const userId = context.params.userId;
        const depois = change.after.data();
        const antes = change.before.data();
        
        if (depois.tipoPerfil !== 'goleiro') return null;

        // 🛑 TRAVA 1: Se o saldo e as multas não mudaram, não faz sentido rodar. Aborta.
        if (antes.saldo === depois.saldo && antes.multasPendentes === depois.multasPendentes) {
            return null;
        }

        const db = admin.firestore();
        const userRef = db.collection('usuarios').doc(userId);

        try {
            // 🛑 TRAVA 2 (TRANSACTION): Garante que, mesmo que rode 2x ao mesmo tempo,
            // a primeira tranca a porta e a segunda é obrigada a ver a conta zerada e ir embora.
            await db.runTransaction(async (transaction) => {
                const userSnap = await transaction.get(userRef);
                const userData = userSnap.data();

                const saldoAtual = userData.saldo || 0;
                const multasAtual = userData.multasPendentes || 0;

                // Se já resolveu o problema (saldo zerou ou multa zerou), sai sem fazer nada.
                if (saldoAtual <= 0 || multasAtual <= 0) return;

                const valorAbatido = Math.min(saldoAtual, multasAtual);

                // Subtrai com segurança
                transaction.update(userRef, {
                    saldo: admin.firestore.FieldValue.increment(-valorAbatido),
                    multasPendentes: admin.firestore.FieldValue.increment(-valorAbatido)
                });

                const extratoRef = userRef.collection('extrato').doc();
                transaction.set(extratoRef, {
                    id: extratoRef.id,
                    idReferencia: 'pagamento_multa',
                    tipo: 'pagamento_multa',
                    valor: valorAbatido,
                    descricao: 'Pagamento de multa abatido do saldo',
                    data: admin.firestore.FieldValue.serverTimestamp(),
                    status: 'concluido'
                });
            });

            console.log(`✅ Sucesso! Gari Financeiro blindado limpou a dívida do goleiro ${userId}.`);
            return null;

        } catch (error) {
            console.error(`🔴 Erro no Gari Financeiro do goleiro ${userId}:`, error);
            return null;
        }
    });

// ============================================================================
// 7. 🏆 GATILHO REATIVO: LEVEL-UP AUTOMÁTICO DO GOLEIRO (PROMOÇÃO DE NÍVEL)
// ============================================================================
exports.recalcularNivelGoleiro = functions.firestore
    .document("avaliacoes_goleiros/{avaliacaoId}")
    .onCreate(async (snap, context) => {
        const avaliacao = snap.data();
        const idGoleiro = avaliacao.idGoleiro;

        if (!idGoleiro) {
            console.log("Avaliação sem idGoleiro, ignorando.");
            return null;
        }

        const db = admin.firestore();
        const goleiroRef = db.collection("usuarios").doc(idGoleiro);

        try {
            // 🟢 LÊ AS REGRAS DO PAINEL DE ADMINISTRADOR PRIMEIRO!
            let reqEliteNota = 4.5;
            let reqElitePartidas = 5;
            let reqExperienteNota = 1.5;
            let reqExperientePartidas = 1;

            const configDoc = await db.collection('configuracoes').doc('global').get();
            if (configDoc.exists) {
                const conf = configDoc.data();
                reqEliteNota = conf.reqEliteNota ?? 4.5;
                reqElitePartidas = conf.reqElitePartidas ?? 5;
                reqExperienteNota = conf.reqExperienteNota ?? 1.5;
                reqExperientePartidas = conf.reqExperientePartidas ?? 1;
            }

            await db.runTransaction(async (transaction) => {
                const goleiroSnap = await transaction.get(goleiroRef);
                if (!goleiroSnap.exists) return;

                const dados = goleiroSnap.data();
                
                // Puxa histórico de avaliações acumuladas
                const somaNotasAtual = (dados.somaNotasAvaliacoes || 0) + (avaliacao.notaGeral || 0);
                const totalAvaliacoesAtual = (dados.totalAvaliacoes || 0) + 1;
                const partidasAtuadas = dados.atuadas || 0;

                // Calcula a nova média (ex: 4.6)
                const novaMedia = parseFloat((somaNotasAtual / totalAvaliacoesAtual).toFixed(2));

                // 📐 Regra de Negócio Dinâmica (Agora respeita o Firebase!)
                let novoNivel = "livre";

                if (partidasAtuadas >= reqElitePartidas && novaMedia >= reqEliteNota) {
                    novoNivel = "elite";
                } else if (partidasAtuadas >= reqExperientePartidas && novaMedia >= reqExperienteNota) {
                    novoNivel = "experiente";
                }

                const nivelAntigo = dados.categoria || "livre";
                const subiuDeNivel = novoNivel !== nivelAntigo;

                // Atualiza perfil do goleiro
                transaction.update(goleiroRef, {
                    somaNotasAvaliacoes: somaNotasAtual,
                    totalAvaliacoes: totalAvaliacoesAtual,
                    notaMedia: novaMedia,
                    categoria: novoNivel,
                    nivelAtualizadoEm: admin.firestore.FieldValue.serverTimestamp()
                });

                // 🔔 Se o goleiro SUBIU de nível, manda aquele Push de parabéns!
                if (subiuDeNivel) {
                    const nomeNivelFormatado = novoNivel === "elite" ? "Elite 🥇" : "Experiente 🛡️";
                    const pushRef = db.collection("notificacoes").doc();
                    
                    transaction.set(pushRef, {
                        idUsuario: idGoleiro,
                        titulo: "PARABÉNS! VOCÊ SUBIU DE NÍVEL! 🎉",
                        mensagem: `Sua dedicação valeu a pena! Você agora é um Goleiro ${nomeNivelFormatado} (Média ${novaMedia}★). Seus jogos agora valem mais!`,
                        tipo: "level_up",
                        data: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            });

            console.log(`✅ Nível do goleiro ${idGoleiro} recalculado com sucesso via regras do painel.`);
            return null;

        } catch (error) {
            console.error(`❌ Erro ao recalcular nível do goleiro ${idGoleiro}:`, error);
            return null;
        }
    });

// ============================================================================
// 8. 💰 GERENCIADOR DE SAQUES & ROBÔ INDEX (Dispara Push + Incrementa Estatísticas)
// ============================================================================
exports.aoAtualizarStatusSaque = functions.firestore
    .document("saques/{idSaque}")
    .onUpdate(async (change, context) => {
        const antes = change.before.data();
        const depois = change.after.data();

        // Se o status não mudou, ignora e encerra
        if (antes.status === depois.status) return null;

        const db = admin.firestore();
        const idGoleiro = depois.idGoleiro;
        const valor = (depois.valor || 0);
        const valorFormatado = valor.toFixed(2).replace('.', ',');

        try {
            // 🟢 AÇÃO 1: SE O SAQUE FOI APROVADO E PAGO
            if (depois.status === 'pago') {
                
                // 1. Incrementa o robô das métricas globais no Index/Dashboard
                const estatisticasRef = db.collection('configuracoes').doc('estatisticas');
                await estatisticasRef.set({
                    totalSaquesLiberados: admin.firestore.FieldValue.increment(1),
                    valorTotalSaquesPai: admin.firestore.FieldValue.increment(valor),
                    ultimaAtualizacao: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });

                // 2. Dispara a notificação Push de vitória para o goleiro!
                if (idGoleiro) {
                    const notifRef = db.collection('notificacoes').doc();
                    await notifRef.set({
                        idUsuario: idGoleiro,
                        titulo: "PIX Enviado com Sucesso! 💰🚀",
                        mensagem: `Seu saque de R$ ${valorFormatado} foi aprovado e o dinheiro já caiu na sua conta cadastrada!`,
                        tipo: "saque_pago",
                        lida: false,
                        data: admin.firestore.FieldValue.serverTimestamp()
                    });
                }

                console.log(`✅ Saque ${context.params.idSaque} pago! Robô incrementado e Push enviado.`);
            }

            // 🔴 AÇÃO 2: SE O SAQUE FOI RECUSADO
            else if (depois.status === 'recusado') {
                if (idGoleiro) {
                    const notifRef = db.collection('notificacoes').doc();
                    await notifRef.set({
                        idUsuario: idGoleiro,
                        titulo: "Solicitação de Saque Recusada ⚠️",
                        mensagem: `Sua solicitação de saque de R$ ${valorFormatado} foi recusada e o saldo retornou para sua carteira.`,
                        tipo: "saque_recusado",
                        lida: false,
                        data: admin.firestore.FieldValue.serverTimestamp()
                    });
                }

                console.log(`⚠️ Saque ${context.params.idSaque} recusado. Notificação de estorno enviada.`);
            }

            return null;

        } catch (error) {
            console.error(`❌ Erro no processamento do saque ${context.params.idSaque}:`, error);
            return null;
        }
    });

// ============================================================================
// 9. GATILHO DE DESISTENCIA (Avisa Contratante + Recibo no Historico)
// ============================================================================
exports.aoGoleiroDesistir = functions.firestore
  .document("jogos/{jogoId}")
  .onUpdate(async (change, context) => {
    const antes = change.before.data();
    const depois = change.after.data();

    const idGoleiroAntes = antes.idGoleiro;
    const idGoleiroDepois = depois.idGoleiro;

    // Condicao exata: Tinha goleiro, agora nao tem mais, e o jogo voltou pra "aberto"
    if (idGoleiroAntes && !idGoleiroDepois && depois.status === "aberto") {
      const db = admin.firestore();
      const idContratante = depois.idContratante;
      const nomeGoleiro = antes.nomeGoleiro || "O goleiro";
      const local = depois.local || "a pelada";
      
      try {
        const batch = db.batch();

        if (idContratante) {
          const notifRef = db.collection("notificacoes").doc();
          batch.set(notifRef, {
            idUsuario: idContratante,
            titulo: "Atencao: Goleiro Desistiu!",
            mensagem: `${nomeGoleiro} cancelou a participacao no jogo em ${local}. A partida voltou automaticamente para o mural!`,
            tipo: "goleiro_desistiu",
            lida: false,
            data: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        const idRecibo = `cancelado_${context.params.jogoId}_${idGoleiroAntes}`;
        const reciboRef = db.collection("jogos").doc(idRecibo);
        
        const dadosRecibo = {
          ...antes,
          status: "cancelado",
          canceladoPor: "goleiro",
          idGoleiro: idGoleiroAntes,
          arquivadoGoleiro: true,
          motivoCancelamento: "Voce desistiu desta partida.",
          dataCancelamento: admin.firestore.FieldValue.serverTimestamp()
        };

        batch.set(reciboRef, dadosRecibo);

        await batch.commit();
        console.log(`Goleiro ${idGoleiroAntes} desistiu. Recibo salvo no historico.`);
        
      } catch (error) {
        console.error(`Erro no gatilho de desistencia do jogo ${context.params.jogoId}:`, error);
      }
    }
    
    return null;
  });

// ============================================================================
// 10. 💬 PUSH DIRETO DE CHAT (Sem poluir a sineta de notificações do app!)
// ============================================================================
exports.notificarNovaMensagemChat = functions.firestore
    .document('jogos/{jogoId}/mensagens/{mensagemId}')
    .onCreate(async (snap, context) => {
        const mensagem = snap.data();
        const jogoId = context.params.jogoId;
        const idRemetente = mensagem.idRemetente;
        const db = admin.firestore();

        try {
            // 1. Buscar os dados do Jogo para contexto e destinatário
            const jogoDoc = await db.collection('jogos').doc(jogoId).get();
            if (!jogoDoc.exists) return null;

            const jogo = jogoDoc.data();
            const idContratante = jogo.idContratante;
            const idGoleiro = jogo.idGoleiro;

            // 2. Descobrir quem é o destinatário
            let idDestinatario = '';
            if (idRemetente === idContratante) {
                idDestinatario = idGoleiro;
            } else if (idRemetente === idGoleiro) {
                idDestinatario = idContratante;
            } else {
                return null;
            }

            if (!idDestinatario) return null;

            // 3. Buscar o Token (FCM) direto no perfil do destinatário
            const destinatarioDoc = await db.collection('usuarios').doc(idDestinatario).get();
            const token = destinatarioDoc.data()?.fcmToken;

            // Se o cara não tem token, encerra aqui (sem dar erro)
            if (!token) {
                console.log(`Destinatário ${idDestinatario} sem token FCM.`);
                return null;
            }

            // 4. Buscar o nome de quem mandou a mensagem
            const remetenteDoc = await db.collection('usuarios').doc(idRemetente).get();
            const nomeRemetente = remetenteDoc.exists ? remetenteDoc.data().nome : 'Nova mensagem';
            const textoMensagem = mensagem.texto ? mensagem.texto : 'Enviou um anexo';

            // 5. 🎯 MONTAR O RESUMO DO JOGO PARA O TÍTULO DO PUSH
            const nomeLocal = (jogo.local || 'Arena').split('(')[0].trim();
            let horaStr = jogo.horaExibicao;
            
            // Fallback de segurança se não achar a hora formatada
            if (!horaStr && jogo.dataHora) {
                const dHora = jogo.dataHora.toDate();
                horaStr = `${String(dHora.getHours()).padStart(2, '0')}:${String(dHora.getMinutes()).padStart(2, '0')}`;
            }

            const resumoJogo = horaStr ? `${nomeLocal} às ${horaStr}` : nomeLocal;

            // 6. 🚀 DISPARAR O PUSH DIRETAMENTE! 
            // (Assim a mensagem vai pro celular, mas NÃO fica salva na "Sineta")
            const payload = {
                token: token,
                notification: {
                    title: `💬 ${nomeRemetente} (${resumoJogo})`, // Ex: 💬 Leandro (HD Sports às 18:00)
                    body: textoMensagem,
                },
                data: {
                    tipo: "chat_jogo",
                    idJogo: jogoId,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK'
                }
            };

            await admin.messaging().send(payload);
            console.log(`✅ Push de chat enviado direto para ${idDestinatario} (Sem ir pra sineta)`);
            return null;

        } catch (error) {
            console.error('❌ Erro ao processar notificação direta de chat:', error);
            return null;
        }
    });

    // ============================================================================
// 11. GARI DE CONTAS: Limpeza Total após exclusão (Hard Delete)
// ============================================================================
exports.limparDadosUsuarioDeletado = functions.auth.user().onDelete(async (user) => {
    const uid = user.uid;
    const db = admin.firestore();

    console.log(`🧹 Iniciando limpeza de dados para o usuário deletado: ${uid}`);

    try {
        const batch = db.batch();
        const userRef = db.collection('usuarios').doc(uid);

        // 1. Deletar a subcoleção 'extrato' (Se existir)
        const extratoSnap = await userRef.collection('extrato').get();
        extratoSnap.forEach((doc) => {
            batch.delete(doc.ref); // 🟢 CORREÇÃO: Usando doc.ref ao invés de doc ou doc.id
        });

        // 2. Deletar as notificações vinculadas ao usuário
        const notificacoesSnap = await db.collection('notificacoes').where('idUsuario', '==', uid).get();
        notificacoesSnap.forEach((doc) => {
            batch.delete(doc.ref); // 🟢 CORREÇÃO: Usando doc.ref
        });

        // 3. Deletar o documento principal do usuário
        batch.delete(userRef);

        await batch.commit();
        console.log(`✅ Limpeza concluída com sucesso para o UID: ${uid}`);

    } catch (error) {
        console.error(`❌ Erro fatal ao limpar dados do usuário ${uid}:`, error);
    }

    return null;
});
 