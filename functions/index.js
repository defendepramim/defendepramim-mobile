const { setGlobalOptions } = require("firebase-functions/v2");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
// 🚀 ADICIONA ESTA LINHA:
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const functionsV1 = require("firebase-functions/v1"); 
const admin = require("firebase-admin");

admin.initializeApp();

// 🚀 Força todas as funções V2 a rodar no Brasil para latência mínima!
setGlobalOptions({ region: "southamerica-east1" });

// Opções padrão para Callables Gen2 (evita ambiguidade de região no deploy)
const CALLABLE_OPTS = {
    region: "southamerica-east1",
    timeoutSeconds: 60,
    memory: "256MiB",
};


// ============================================================================
// 0. MÁQUINA DE ESTADOS (A Fonte da Verdade)
// ============================================================================
const ESTADOS_PERMITIDOS = {
    "aberto": ["fechado", "cancelado", "expirado"],
    "fechado": ["aberto", "cancelado", "finalizado", "contestado"],
    "contestado": ["contestado_aceito", "finalizado", "cancelado"],
    "cancelado": [],
    "expirado": [],
    "finalizado": [],
    "contestado_aceito": []
};

function validarTransicao(estadoAntigo, estadoNovo) {
    if (!ESTADOS_PERMITIDOS[estadoAntigo]) return false;
    return ESTADOS_PERMITIDOS[estadoAntigo].includes(estadoNovo);
}

// ============================================================================
// 1. FUNDAÇÃO: CRIAR PERFIL E CARTEIRA (V1 Auth - 100% Gratuito)
// ============================================================================
exports.criarPerfilECarteira = functionsV1.region("southamerica-east1").auth.user().onCreate(async (user) => {
    const db = admin.firestore();

    try {
        const batch = db.batch();
        const userRef = db.collection('usuarios').doc(user.uid);
        const carteiraRef = db.collection('carteiras').doc(user.uid);

        batch.set(carteiraRef, {
            saldoCentavos: 0,
            multasPendentesCentavos: 0,
            retidoCentavos: 0,
            atualizadoEm: admin.firestore.FieldValue.serverTimestamp()
        });

        batch.set(userRef, {
            uid: user.uid,
            email: user.email ? user.email.toLowerCase() : null,
            nome: user.displayName || "Novo Usuário",
            fotoUrl: user.photoURL || "",
            categoria: "livre",
            ativo: true,
            criadoEm: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        await batch.commit();
        console.log(`[LEDGER] Carteira criada com sucesso para ${user.uid}`);
        return null;
    } catch (error) {
        console.error(`[ERRO CRÍTICO] Falha ao criar carteira para ${user.uid}:`, error);
        return null;
    }
});

// ============================================================================
// 2. ROBÔ DE EXPIRAÇÃO DE JOGOS ABERTOS (V2)
// ============================================================================
exports.expirarJogosAbertos = onSchedule("every 15 minutes", async () => {
    const db = admin.firestore();
    const agora = admin.firestore.Timestamp.now();

    const jogosVencidos = await db.collection("jogos")
        .where("status", "==", "aberto")
        .where("dataHora", "<", agora)
        .get();

    if (jogosVencidos.empty) return;

    console.log(`[JOB] Encontrados ${jogosVencidos.size} jogos abertos e vencidos.`);
    const promessas = [];

    for (const doc of jogosVencidos.docs) {
        const idJogo = doc.id;

        if (!validarTransicao("aberto", "expirado")) continue;

        const jogoRef = db.collection("jogos").doc(idJogo);
        const ledgerRef = db.collection("ledger").doc(`estorno_expirado_${idJogo}`);

        const operacao = db.runTransaction(async (transaction) => {
            // ===== LEITURAS PRIMEIRO =====
            const jSnap = await transaction.get(jogoRef);
            if (!jSnap.exists) return;
            const jogo = jSnap.data();
            if (jogo.status !== "aberto") return;

            let estornoCentavos = 0;
            if (typeof jogo.pagoEmCentavos === "number" && jogo.pagoEmCentavos > 0) {
                estornoCentavos = Math.round(jogo.pagoEmCentavos);
            } else if (jogo.statusPagamento === "pago" && typeof jogo.valor === "number") {
                estornoCentavos = Math.round(jogo.valor * 100);
            }

            let saldoAtual = 0;
            let jaEstornou = false;
            const carteiraRef = jogo.idContratante
                ? db.collection("carteiras").doc(jogo.idContratante)
                : null;

            if (estornoCentavos > 0 && carteiraRef) {
                const ledgerSnap = await transaction.get(ledgerRef);
                jaEstornou = ledgerSnap.exists;
                if (!jaEstornou) {
                    const cSnap = await transaction.get(carteiraRef);
                    saldoAtual = cSnap.exists ? (cSnap.data().saldoCentavos || 0) : 0;
                }
            }

            // ===== ESCRITAS =====
            transaction.update(jogoRef, {
                status: "expirado",
                motivoCancelamento: "O horário passou e nenhum goleiro aceitou a convocação.",
                expiradoEm: admin.firestore.FieldValue.serverTimestamp(),
                editadoEm: admin.firestore.FieldValue.serverTimestamp(),
                valorEstornadoCentavos: estornoCentavos,
            });

            if (estornoCentavos > 0 && carteiraRef && !jaEstornou) {
                const novoSaldo = saldoAtual + estornoCentavos;
                transaction.set(carteiraRef, {
                    saldoCentavos: novoSaldo,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                transaction.set(ledgerRef, {
                    tipo: "estorno_expirado",
                    uid: jogo.idContratante,
                    idJogo: idJogo,
                    valorCentavos: estornoCentavos,
                    saldoAposCentavos: novoSaldo,
                    idempotencyKey: `estorno_expirado_${idJogo}`,
                    descricao: `Estorno: jogo expirado sem goleiro (${jogo.local || idJogo})`,
                    origem: "expirarJogosAbertos",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            if (jogo.idContratante) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: jogo.idContratante,
                    titulo: "Atenção: Jogo Expirado ⏰",
                    mensagem: `O seu jogo em ${jogo.local || "a arena"} não encontrou goleiros a tempo. O valor foi estornado para a sua carteira.`,
                    tipo: "jogo_expirado",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`[JOB] Expirado jogo=${idJogo} estorno=${estornoCentavos}c`);
        });

        promessas.push(operacao);
    }

    const results = await Promise.allSettled(promessas);
    const falhas = results.filter((r) => r.status === "rejected");
    if (falhas.length) {
        console.error(`[JOB] ${falhas.length} expiração(ões) falharam:`, falhas.map((f) => f.reason));
    }
});


exports.notificarNovaPelada = onDocumentCreated("jogos/{jogoId}", async (event) => {
    if (!event.data) return;
    const jogo = event.data.data();
    const db = admin.firestore();

    if (jogo.status !== 'aberto' || event.params.jogoId.startsWith('cancelado_')) return;

    const agoraUtc = new Date();
    let horaBrasil = agoraUtc.getUTCHours() - 3;
    if (horaBrasil < 0) horaBrasil += 24;

    if (horaBrasil < 8 || horaBrasil >= 22) return; 

    const jogoLat = jogo.latitude || jogo.lat;
    const jogoLng = jogo.longitude || jogo.lng;
    if (!jogoLat || !jogoLng) return;

    const nivelExigidoStr = (jogo.nivelGoleiro || jogo.nivel || 'livre').toLowerCase();
    let rankExigido = 0; 
    
    if (nivelExigidoStr.includes('elite') || nivelExigidoStr.includes('pared')) rankExigido = 2;
    else if (nivelExigidoStr.includes('exp') || nivelExigidoStr.includes('inter') || nivelExigidoStr.includes('médio') || nivelExigidoStr.includes('medio')) rankExigido = 1;

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
        const tokensCelularesProcessados = new Set();

        for (const doc of goleirosSnap.docs) {
            const goleiro = doc.data();
            if (!goleiro.lat || !goleiro.lng) continue;
            if (goleiro.fcmToken) {
                if (tokensCelularesProcessados.has(goleiro.fcmToken)) continue;
                tokensCelularesProcessados.add(goleiro.fcmToken);
            }

            const distancia = calcularDistancia(jogoLat, jogoLng, goleiro.lat, goleiro.lng);
            if (distancia > 10) continue;

            const nivelGoleiro = (goleiro.categoria || 'livre').toLowerCase();
            let rankGoleiro = 0;
            
            if (nivelGoleiro.includes('elite') || nivelGoleiro.includes('pared')) rankGoleiro = 2;
            else if (nivelGoleiro.includes('exp') || nivelGoleiro.includes('inter') || nivelGoleiro.includes('médio') || nivelGoleiro.includes('medio')) rankGoleiro = 1;

            if (rankGoleiro < rankExigido) continue;

            // Limite diário removido daqui (era N+1 reads). Controlar via config/contador no perfil se necessário.
            const dHora = jogo.dataHora ? jogo.dataHora.toDate() : new Date();
            const diaMes = jogo.dataExibicao || `${String(dHora.getDate()).padStart(2, "0")}/${String(dHora.getMonth() + 1).padStart(2, "0")}`;
            const horaStr = jogo.horaExibicao || `${String(dHora.getHours()).padStart(2, "0")}:${String(dHora.getMinutes()).padStart(2, "0")}`;

            const novaNotificacaoRef = db.collection('notificacoes').doc();
            batch.set(novaNotificacaoRef, {
                idUsuario: doc.id,
                titulo: "⚽ Nova Convocação na Área!",
                mensagem: `Pelada de R$ ${Number(valorParaGoleiro).toFixed(2)} dia ${diaMes} às ${horaStr} a apenas ${distancia.toFixed(1)}km de você!`,
                tipo: "nova_pelada",
                idJogo: event.params.jogoId,
                lida: false,
                data: admin.firestore.FieldValue.serverTimestamp()
            });
            notificacoesGeradas++;
        }
        if (notificacoesGeradas > 0) await batch.commit();

    } catch (error) {
        console.error("Erro fatal ao processar envio:", error);
    }
});
    
// ============================================================================
// 4. PUSH UNIVERSAL (V2)
// ============================================================================
exports.dispararPushUniversal = onDocumentCreated("notificacoes/{docId}", async (event) => {
    if (!event.data) return;
    const notificacao = event.data.data();
    const idUsuarioDestino = notificacao.idUsuario;

    if (!idUsuarioDestino || notificacao.publicoAlvo) return;

    try {
        const userDoc = await admin.firestore().collection("usuarios").doc(idUsuarioDestino).get();
        const token = userDoc.data()?.fcmToken;
        if (!token) return;

        const payload = {
            token: token,
            notification: { title: notificacao.titulo, body: notificacao.mensagem },
            data: { tipo: notificacao.tipo || 'geral', click_action: 'FLUTTER_NOTIFICATION_CLICK' }
        };

        if (notificacao.idJogo) payload.data.idJogo = String(notificacao.idJogo);

        await admin.messaging().send(payload);
    } catch (error) {
        console.error(`❌ Erro no Push Universal:`, error);
    }
});

// ============================================================================
// 5. DISPARO EM MASSA PELO PAINEL ADMIN (V2)
// ============================================================================
exports.dispararNotificacaoAdmin = onDocumentCreated("notificacoes/{docId}", async (event) => {
    if (!event.data) return;
    const dados = event.data.data();
    const alvo = dados.publicoAlvo; 

    if (!alvo) return;

    try {
        let query = admin.firestore().collection("usuarios");
        if (alvo !== "todos") query = query.where("tipoPerfil", "==", alvo);

        const usuariosSnapshot = await query.get();
        const tokens = [];

        usuariosSnapshot.forEach((doc) => {
            const fcmToken = doc.data().fcmToken;
            if (fcmToken) tokens.push(fcmToken);
        });

        if (tokens.length === 0) return event.data.ref.update({ status: "sem_destinatarios" });

        const payload = {
            notification: { title: dados.titulo, body: dados.mensagem },
            tokens: tokens,
        };

        const response = await admin.messaging().sendMulticast(payload);
        
        return event.data.ref.update({ 
            status: "concluido",
            sucessos: response.successCount,
            falhas: response.failureCount,
            dataProcessamento: admin.firestore.FieldValue.serverTimestamp()
        });

    } catch (error) {
        return event.data.ref.update({ status: "erro_no_envio", erro: error.message });
    }
});

// ============================================================================
// 6. ROBÔ DE PAGAMENTO AUTOMÁTICO (V2) — MODELO OFICIAL (centavos + carteiras + ledger)
// ============================================================================
// Regras:
// - Dinheiro só em centavos (int)
// - Saldo oficial só em carteiras/{uid}.saldoCentavos
// - Histórico imutável em ledger/{idempotencyKey}
// - IdempotencyKey estável: recebimento_{jogoId} (job pode correr 2x sem pagar 2x)
// - NUNCA escrever usuarios.saldo / extrato legado
// ============================================================================
exports.rotinaPagamentoAutomatico = onSchedule("every 1 hours", async () => {
    const db = admin.firestore();
    const agora = admin.firestore.Timestamp.now();

    const jogosSnapshot = await db.collection("jogos").where("status", "==", "fechado").get();
    if (jogosSnapshot.empty) return;

    // Taxas de fallback (R$) — só usadas se o jogo NÃO tiver valor congelado
    let taxaAppElite = 9.0;
    let taxaAppInter = 8.0;
    let taxaAppVarzea = 7.0;
    let horasPagamentoAuto = 12;

    try {
        const configDoc = await db.collection("configuracoes").doc("global").get();
        if (configDoc.exists) {
            const conf = configDoc.data();
            taxaAppElite = conf.taxaAppElite ?? 9.0;
            taxaAppInter = conf.taxaAppInter ?? 8.0;
            taxaAppVarzea = conf.taxaAppVarzea ?? 7.0;
            horasPagamentoAuto = conf.horasPagamentoAuto ?? 12;
        }
    } catch (e) {
        console.error("[PAGAMENTO_AUTO] Falha ao ler configuracoes/global:", e);
    }

    const promessas = [];

    for (const doc of jogosSnapshot.docs) {
        const dados = doc.data();
        if (!dados.dataHora || !dados.idGoleiro) continue;

        const dataHoraJogo = dados.dataHora.toDate();
        const duracaoMin = dados.duracao || 60;
        const msHorasAuto = horasPagamentoAuto * 3600000;
        const limitePagamento = new Date(
            dataHoraJogo.getTime() + (duracaoMin * 60000) + msHorasAuto
        );

        if (agora.toDate() <= limitePagamento) continue;

        const idJogo = doc.id;
        const idGoleiro = dados.idGoleiro;

        // ------------------------------------------------------------------
        // Cálculo do repasse em CENTAVOS (prioridade: valores congelados no jogo)
        // ------------------------------------------------------------------
        let valorRepasseCentavos = 0;

        if (typeof dados.valorGoleiroCentavos === "number" && dados.valorGoleiroCentavos >= 0) {
            // Caminho ideal (futuro): já gravado em centavos na criação/pagamento
            valorRepasseCentavos = Math.round(dados.valorGoleiroCentavos);
        } else if (typeof dados.pagoEmCentavos === "number" && dados.pagoEmCentavos > 0) {
            // Contratante pagou X centavos; descontar taxa se existir
            const pago = Math.round(dados.pagoEmCentavos);
            if (typeof dados.taxaAplicadaCentavos === "number") {
                valorRepasseCentavos = Math.max(0, pago - Math.round(dados.taxaAplicadaCentavos));
            } else if (typeof dados.taxaAplicada === "number") {
                // taxaAplicada legada em R$
                valorRepasseCentavos = Math.max(0, pago - Math.round(dados.taxaAplicada * 100));
            } else {
                // Sem taxa gravada: usa config por nível
                const nivel = (dados.nivelGoleiro || dados.nivel || "").toLowerCase();
                let taxaReais = taxaAppVarzea;
                if (nivel.includes("elite")) taxaReais = taxaAppElite;
                else if (nivel.includes("inter") || nivel.includes("experiente")) taxaReais = taxaAppInter;
                const horas = (dados.duracao || 60) / 60;
                valorRepasseCentavos = Math.max(0, pago - Math.round(taxaReais * horas * 100));
            }
        } else if (typeof dados.valorGoleiro === "number" && dados.valorGoleiro >= 0) {
            // Legado: valorGoleiro em R$
            valorRepasseCentavos = Math.round(dados.valorGoleiro * 100);
        } else {
            // Último recurso: valor total do jogo - taxa da config
            const valorTotalReais = typeof dados.valor === "number" ? dados.valor : 0;
            const nivel = (dados.nivelGoleiro || dados.nivel || "").toLowerCase();
            let taxaReais = taxaAppVarzea;
            if (nivel.includes("elite")) taxaReais = taxaAppElite;
            else if (nivel.includes("inter") || nivel.includes("experiente")) taxaReais = taxaAppInter;
            const horas = (dados.duracao || 60) / 60;
            valorRepasseCentavos = Math.max(0, Math.round((valorTotalReais - (taxaReais * horas)) * 100));
        }

        if (valorRepasseCentavos <= 0) {
            console.warn(`[PAGAMENTO_AUTO] Jogo ${idJogo} com repasse 0 — apenas finaliza status.`);
        }

        const jogoRef = db.collection("jogos").doc(idJogo);
        const carteiraRef = db.collection("carteiras").doc(idGoleiro);
        const goleiroRef = db.collection("usuarios").doc(idGoleiro);
        // Idempotency ESTÁVEL: se o job correr de novo, o ledger já existe e aborta o crédito
        const ledgerRef = db.collection("ledger").doc(`recebimento_${idJogo}`);

        const operacao = db.runTransaction(async (transaction) => {
            const jSnap = await transaction.get(jogoRef);
            if (!jSnap.exists) return;

            const jogoAtual = jSnap.data();
            if (jogoAtual.status !== "fechado") {
                console.log(`[PAGAMENTO_AUTO] Jogo ${idJogo} já não está fechado (${jogoAtual.status}). Skip.`);
                return;
            }

            if (!validarTransicao("fechado", "finalizado")) {
                console.error(`[PAGAMENTO_AUTO] Transição fechado→finalizado inválida para ${idJogo}`);
                return;
            }

            // Anti-duplo pagamento: ledger com ID estável
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                console.log(`[PAGAMENTO_AUTO] Ledger recebimento_${idJogo} já existe. Só garante status finalizado.`);
                transaction.update(jogoRef, {
                    status: "finalizado",
                    finalizadoAutomaticamente: true,
                    pagoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
                return;
            }

            // --- Carteira do goleiro ---
            const carteiraSnap = await transaction.get(carteiraRef);
            const saldoAtual = carteiraSnap.exists
                ? (carteiraSnap.data().saldoCentavos || 0)
                : 0;
            const novoSaldo = saldoAtual + valorRepasseCentavos;

            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            // --- Ledger imutável ---
            transaction.set(ledgerRef, {
                tipo: "recebimento_jogo",
                uid: idGoleiro,
                idJogo: idJogo,
                valorCentavos: valorRepasseCentavos,
                saldoAposCentavos: novoSaldo,
                idempotencyKey: `recebimento_${idJogo}`,
                descricao: `Recebimento automático: ${dados.local || "Pelada"}`,
                origem: "rotina_pagamento_automatico",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            // --- Jogo → finalizado ---
            transaction.update(jogoRef, {
                status: "finalizado",
                pagoEm: admin.firestore.FieldValue.serverTimestamp(),
                finalizadoAutomaticamente: true,
                valorPagoAoGoleiroCentavos: valorRepasseCentavos,
                // Campo legado em R$ só para compatibilidade de UI antiga (remover depois)
                valorPagoAoGoleiro: valorRepasseCentavos / 100,
            });

            // --- Stats NÃO financeiras no perfil (ok em usuarios) ---
            transaction.set(goleiroRef, {
                totalGanhosCentavos: admin.firestore.FieldValue.increment(valorRepasseCentavos),
                atuadas: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            if (dados.idContratante) {
                const contratanteRef = db.collection("usuarios").doc(dados.idContratante);
                transaction.set(contratanteRef, {
                    jogosRealizados: admin.firestore.FieldValue.increment(1),
                    partidasOrganizadas: admin.firestore.FieldValue.increment(1),
                }, { merge: true });
            }

            // --- Push para o goleiro ---
            const pushRef = db.collection("notificacoes").doc();
            transaction.set(pushRef, {
                idUsuario: idGoleiro,
                titulo: "Pagamento recebido! 💰",
                mensagem: `R$ ${(valorRepasseCentavos / 100).toFixed(2).replace(".", ",")} da pelada em ${dados.local || "sua arena"} já está na sua carteira.`,
                tipo: "recebimento_jogo",
                idJogo: idJogo,
                lida: false,
                data: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`[PAGAMENTO_AUTO] Jogo ${idJogo} → +${valorRepasseCentavos} centavos para ${idGoleiro}`);
        });

        promessas.push(operacao);
    }

    const resultados = await Promise.allSettled(promessas);
    const falhas = resultados.filter((r) => r.status === "rejected");
    if (falhas.length > 0) {
        console.error(`[PAGAMENTO_AUTO] ${falhas.length} transação(ões) falharam:`, falhas);
    }
});

// ============================================================================
// 7. GARI FINANCEIRO (V2) — MODELO OFICIAL (centavos + carteiras + ledger)
// ============================================================================
// Escuta carteiras/{uid}. Quando há saldo E multa pendente, abate automaticamente.
// Proteção anti-loop: se saldoCentavos <= 0 ou multasPendentesCentavos <= 0, sai.
// NUNCA mexe em usuarios.saldo / extrato legado.
// ============================================================================
exports.abaterMultaAutomatica = onDocumentUpdated("carteiras/{userId}", async (event) => {
    if (!event.data) return;

    const userId = event.params.userId;
    const antes = event.data.before.data() || {};
    const depois = event.data.after.data() || {};

    const saldoAntes = antes.saldoCentavos || 0;
    const saldoDepois = depois.saldoCentavos || 0;
    const multasAntes = antes.multasPendentesCentavos || 0;
    const multasDepois = depois.multasPendentesCentavos || 0;

    // Só age se saldo ou multas mudaram de forma relevante
    if (saldoAntes === saldoDepois && multasAntes === multasDepois) return;

    // Sem saldo ou sem multa → nada a fazer (também corta o loop do próprio abatimento)
    if (saldoDepois <= 0 || multasDepois <= 0) return;

    const db = admin.firestore();
    const carteiraRef = db.collection("carteiras").doc(userId);

    try {
        await db.runTransaction(async (transaction) => {
            const carteiraSnap = await transaction.get(carteiraRef);
            if (!carteiraSnap.exists) return;

            const data = carteiraSnap.data();
            const saldoAtual = data.saldoCentavos || 0;
            const multasAtual = data.multasPendentesCentavos || 0;

            if (saldoAtual <= 0 || multasAtual <= 0) return;

            const valorAbatidoCentavos = Math.min(saldoAtual, multasAtual);
            if (valorAbatidoCentavos <= 0) return;

            const novoSaldo = saldoAtual - valorAbatidoCentavos;
            const novasMultas = multasAtual - valorAbatidoCentavos;

            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                multasPendentesCentavos: novasMultas,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            // Ledger imutável (ID único por evento de abatimento)
            const ledgerRef = db.collection("ledger").doc();
            transaction.set(ledgerRef, {
                tipo: "abatimento_multa",
                uid: userId,
                valorCentavos: valorAbatidoCentavos,
                saldoAposCentavos: novoSaldo,
                multasAposCentavos: novasMultas,
                idempotencyKey: ledgerRef.id,
                descricao: "Abatimento automático de multa pendente",
                origem: "gari_financeiro",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notificação ao utilizador
            const pushRef = db.collection("notificacoes").doc();
            transaction.set(pushRef, {
                idUsuario: userId,
                titulo: "Multa abatida do saldo",
                mensagem: `R$ ${(valorAbatidoCentavos / 100).toFixed(2).replace(".", ",")} foram usados para pagar multa pendente.`,
                tipo: "abatimento_multa",
                lida: false,
                data: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`[GARI] uid=${userId} abatido=${valorAbatidoCentavos} centavos | saldo=${novoSaldo} multas=${novasMultas}`);
        });
    } catch (error) {
        console.error(`[GARI] Erro ao abater multa de ${userId}:`, error);
    }
});

// ============================================================================
// 8. LEVEL-UP GOLEIRO (V2)
// ============================================================================
exports.recalcularNivelGoleiro = onDocumentCreated("avaliacoes_goleiros/{avaliacaoId}", async (event) => {
    if (!event.data) return;
    const avaliacao = event.data.data();
    const idGoleiro = avaliacao.idGoleiro;

    if (!idGoleiro) return;
    const db = admin.firestore();
    const goleiroRef = db.collection("usuarios").doc(idGoleiro);

    try {
        // Defaults alinhados com Flutter / painel (configuracoes/global sobrescreve)
        let reqEliteNota = 4.5, reqElitePartidas = 15, reqExperienteNota = 4.2, reqExperientePartidas = 5;

        const configDoc = await db.collection('configuracoes').doc('global').get();
        if (configDoc.exists) {
            const conf = configDoc.data();
            reqEliteNota = conf.reqEliteNota ?? 4.5;
            reqElitePartidas = conf.reqElitePartidas ?? 15;
            reqExperienteNota = conf.reqExperienteNota ?? 4.2;
            reqExperientePartidas = conf.reqExperientePartidas ?? 5;
        }

        await db.runTransaction(async (transaction) => {
            const goleiroSnap = await transaction.get(goleiroRef);
            if (!goleiroSnap.exists) return;

            const dados = goleiroSnap.data();
            const somaNotasAtual = (dados.somaNotasAvaliacoes || 0) + (avaliacao.notaGeral || 0);
            const totalAvaliacoesAtual = (dados.totalAvaliacoes || 0) + 1;
            const partidasAtuadas = dados.atuadas || 0;

            const novaMedia = parseFloat((somaNotasAtual / totalAvaliacoesAtual).toFixed(2));
            let novoNivel = "livre";

            if (partidasAtuadas >= reqElitePartidas && novaMedia >= reqEliteNota) novoNivel = "elite";
            else if (partidasAtuadas >= reqExperientePartidas && novaMedia >= reqExperienteNota) novoNivel = "experiente";

            const subiuDeNivel = novoNivel !== (dados.categoria || "livre");

            transaction.update(goleiroRef, {
                somaNotasAvaliacoes: somaNotasAtual,
                totalAvaliacoes: totalAvaliacoesAtual,
                notaMedia: novaMedia,
                categoria: novoNivel,
                nivelAtualizadoEm: admin.firestore.FieldValue.serverTimestamp()
            });

            if (subiuDeNivel) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: idGoleiro,
                    titulo: "PARABÉNS! VOCÊ SUBIU DE NÍVEL! 🎉",
                    mensagem: `Sua dedicação valeu a pena! Você agora é um Goleiro ${novoNivel.toUpperCase()} (Média ${novaMedia}★).`,
                    tipo: "level_up",
                    data: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        });
    } catch (error) {
        console.error(error);
    }
});

// ============================================================================
// ============================================================================
// 9. GERENCIADOR DE SAQUES (V2) — carteiras + ledger em centavos
// ============================================================================
// - pago: só estatísticas + notificação (dinheiro já saiu em solicitarSaque)
// - recusado: devolve valorCentavos para carteiras + ledger saque_recusado
// ============================================================================
exports.aoAtualizarStatusSaque = onDocumentUpdated("saques/{idSaque}", async (event) => {
    if (!event.data) return;

    const antes = event.data.before.data() || {};
    const depois = event.data.after.data() || {};

    if (antes.status === depois.status) return;

    const db = admin.firestore();
    const idSaque = event.params.idSaque;
    const idGoleiro = depois.idGoleiro;
    // Preferir centavos; fallback legado R$ → centavos
    let valorCentavos = 0;
    if (typeof depois.valorCentavos === "number") {
        valorCentavos = Math.round(depois.valorCentavos);
    } else if (typeof depois.valor === "number") {
        valorCentavos = Math.round(depois.valor * 100);
    }

    try {
        if (depois.status === "pago") {
            await db.collection("configuracoes").doc("estatisticas").set({
                totalSaquesLiberados: admin.firestore.FieldValue.increment(1),
                valorTotalSaquesCentavos: admin.firestore.FieldValue.increment(valorCentavos),
                ultimaAtualizacao: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            // Ledger de confirmação (idempotente)
            const ledgerPagoRef = db.collection("ledger").doc(`saque_pago_${idSaque}`);
            await db.runTransaction(async (transaction) => {
                const snap = await transaction.get(ledgerPagoRef);
                if (snap.exists) return;
                transaction.set(ledgerPagoRef, {
                    tipo: "saque_pago",
                    uid: idGoleiro,
                    idSaque: idSaque,
                    valorCentavos: valorCentavos,
                    idempotencyKey: `saque_pago_${idSaque}`,
                    descricao: "Saque PIX confirmado pelo admin",
                    origem: "aoAtualizarStatusSaque",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
            });

            if (idGoleiro) {
                await db.collection("notificacoes").doc().set({
                    idUsuario: idGoleiro,
                    titulo: "PIX Enviado com Sucesso! 💰",
                    mensagem: `Seu saque de R$ ${(valorCentavos / 100).toFixed(2).replace(".", ",")} foi aprovado e enviado.`,
                    tipo: "saque_pago",
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        } else if (depois.status === "recusado") {
            if (!idGoleiro || valorCentavos <= 0) return;

            const carteiraRef = db.collection("carteiras").doc(idGoleiro);
            const ledgerRef = db.collection("ledger").doc(`saque_recusado_${idSaque}`);

            await db.runTransaction(async (transaction) => {
                const ledgerSnap = await transaction.get(ledgerRef);
                if (ledgerSnap.exists) {
                    console.log(`[SAQUE] Estorno já feito para ${idSaque}`);
                    return;
                }

                const carteiraSnap = await transaction.get(carteiraRef);
                const saldoAtual = carteiraSnap.exists
                    ? (carteiraSnap.data().saldoCentavos || 0)
                    : 0;
                const novoSaldo = saldoAtual + valorCentavos;

                transaction.set(carteiraRef, {
                    saldoCentavos: novoSaldo,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                transaction.set(ledgerRef, {
                    tipo: "saque_recusado",
                    uid: idGoleiro,
                    idSaque: idSaque,
                    valorCentavos: valorCentavos,
                    saldoAposCentavos: novoSaldo,
                    idempotencyKey: `saque_recusado_${idSaque}`,
                    descricao: "Estorno de saque recusado pelo admin",
                    origem: "aoAtualizarStatusSaque",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
            });

            await db.collection("notificacoes").doc().set({
                idUsuario: idGoleiro,
                titulo: "Solicitação de Saque Recusada",
                mensagem: `Sua solicitação foi recusada. R$ ${(valorCentavos / 100).toFixed(2).replace(".", ",")} voltaram para sua carteira.`,
                tipo: "saque_recusado",
                lida: false,
                data: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
    } catch (error) {
        console.error(`[SAQUE] Erro no status ${depois.status} de ${idSaque}:`, error);
    }
});

// 10. GATILHO DE DESISTÊNCIA (V2)
// ============================================================================
exports.aoGoleiroDesistir = onDocumentUpdated("jogos/{jogoId}", async (event) => {
    const antes = event.data.before.data();
    const depois = event.data.after.data();

    if (antes.idGoleiro && !depois.idGoleiro && depois.status === "aberto") {
      const db = admin.firestore();
      try {
        const batch = db.batch();

        if (depois.idContratante) {
          const notifRef = db.collection("notificacoes").doc();
          batch.set(notifRef, {
            idUsuario: depois.idContratante,
            titulo: "Atenção: Goleiro Desistiu!",
            mensagem: `O goleiro cancelou a participação. A partida voltou para o mural!`,
            tipo: "goleiro_desistiu",
            lida: false,
            data: admin.firestore.FieldValue.serverTimestamp()
          });
        }

        const idRecibo = `cancelado_${event.params.jogoId}_${antes.idGoleiro}`;
        batch.set(db.collection("jogos").doc(idRecibo), {
          ...antes,
          status: "cancelado",
          canceladoPor: "goleiro",
          idGoleiro: antes.idGoleiro,
          arquivadoGoleiro: true,
          motivoCancelamento: "Você desistiu desta partida.",
          dataCancelamento: admin.firestore.FieldValue.serverTimestamp()
        });

        await batch.commit();
      } catch (error) {
        console.error(error);
      }
    }
});

// ============================================================================
// 11. PUSH DIRETO DE CHAT (V2)
// ============================================================================
exports.notificarNovaMensagemChat = onDocumentCreated("jogos/{jogoId}/mensagens/{mensagemId}", async (event) => {
    if (!event.data) return;
    const mensagem = event.data.data();
    const db = admin.firestore();

    try {
        const jogoDoc = await db.collection('jogos').doc(event.params.jogoId).get();
        if (!jogoDoc.exists) return;
        const jogo = jogoDoc.data();

        let idDestinatario = '';
        if (mensagem.idRemetente === jogo.idContratante) idDestinatario = jogo.idGoleiro;
        else if (mensagem.idRemetente === jogo.idGoleiro) idDestinatario = jogo.idContratante;

        if (!idDestinatario) return;

        const destinatarioDoc = await db.collection('usuarios').doc(idDestinatario).get();
        const token = destinatarioDoc.data()?.fcmToken;
        if (!token) return;

        const payload = {
            token: token,
            notification: {
                title: `💬 Nova mensagem na pelada`,
                body: mensagem.texto ? mensagem.texto : 'Enviou um anexo',
            },
            data: {
                tipo: "chat_jogo",
                idJogo: event.params.jogoId,
                click_action: 'FLUTTER_NOTIFICATION_CLICK'
            }
        };

        await admin.messaging().send(payload);
    } catch (error) {
        console.error(error);
    }
});

// ============================================================================
// 12. GARI DE CONTAS (V1 Auth - 100% Gratuito)
// ============================================================================
exports.limparDadosUsuarioDeletado = functionsV1.region("southamerica-east1").auth.user().onDelete(async (user) => {
    const db = admin.firestore();
    try {
        const batch = db.batch();
        const userRef = db.collection("usuarios").doc(user.uid);
        const carteiraRef = db.collection("carteiras").doc(user.uid);

        // Extrato legado (se existir)
        const extratoSnap = await userRef.collection("extrato").get();
        extratoSnap.forEach((doc) => batch.delete(doc.ref));

        // Notificações do utilizador
        const notificacoesSnap = await db.collection("notificacoes").where("idUsuario", "==", user.uid).get();
        notificacoesSnap.forEach((doc) => batch.delete(doc.ref));

        // Perfil + carteira oficial
        batch.delete(userRef);
        batch.delete(carteiraRef);

        await batch.commit();
        console.log(`[GARI_CONTAS] Dados limpos para uid=${user.uid}`);
    } catch (error) {
        console.error(`[GARI_CONTAS] Erro ao limpar ${user.uid}:`, error);
    }
    return null;
});

// ============================================================================
// ============================================================================
// 13. 💰 FUNDAÇÃO FINANCEIRA: RECARGAR CARTEIRA (V2 Callable) — HARDENED
// ============================================================================
// Regras:
// - valorCentavos: inteiro positivo
// - idempotencyKey obrigatória → ID do ledger (anti clique-duplo)
// - Só credita carteiras/{uid}.saldoCentavos
// - Preserva multasPendentesCentavos / retidoCentavos (merge)
// - NOTA: no beta isto é recarga de teste; gateway real entra depois
// ============================================================================
exports.recarregarCarteira = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");
    }

    const valorCentavosRaw = request.data?.valorCentavos;
    const idempotencyKey = request.data?.idempotencyKey;

    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const valorCentavos = Number(valorCentavosRaw);
    if (!Number.isFinite(valorCentavos) || !Number.isInteger(valorCentavos) || valorCentavos <= 0) {
        throw new HttpsError("invalid-argument", "valorCentavos deve ser um inteiro positivo (centavos).");
    }

    // Mínimo R$ 1,00 / máximo R$ 5.000,00 (ajuste via config no futuro se precisares)
    const MIN_CENTAVOS = 100;
    const MAX_CENTAVOS = 500000;
    if (valorCentavos < MIN_CENTAVOS) {
        throw new HttpsError("invalid-argument", "Valor mínimo de recarga: R$ 1,00.");
    }
    if (valorCentavos > MAX_CENTAVOS) {
        throw new HttpsError("invalid-argument", "Valor máximo de recarga: R$ 5.000,00.");
    }

    const db = admin.firestore();
    const carteiraRef = db.collection("carteiras").doc(uid);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);

    try {
        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                const prev = ledgerSnap.data();
                console.log(`[RECARGA] Duplicado ignorado: ${idempotencyKey}`);
                return {
                    sucesso: true,
                    mensagem: "Transação já processada.",
                    novoSaldoCentavos: prev.saldoAposCentavos ?? null,
                    jaProcessado: true,
                };
            }

            const carteiraSnap = await transaction.get(carteiraRef);
            const dadosCarteira = carteiraSnap.exists ? carteiraSnap.data() : {};
            const saldoAtual = dadosCarteira.saldoCentavos || 0;
            const novoSaldo = saldoAtual + valorCentavos;

            // Merge: não apaga multas/retido se a carteira já existir
            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                multasPendentesCentavos: dadosCarteira.multasPendentesCentavos || 0,
                retidoCentavos: dadosCarteira.retidoCentavos || 0,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            transaction.set(ledgerRef, {
                tipo: "recarga",
                uid: uid,
                valorCentavos: valorCentavos,
                saldoAposCentavos: novoSaldo,
                idempotencyKey: idempotencyKey,
                descricao: "Recarga de saldo",
                origem: "recarregarCarteira",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`[RECARGA] uid=${uid} +${valorCentavos} centavos → saldo=${novoSaldo}`);

            return {
                sucesso: true,
                novoSaldoCentavos: novoSaldo,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[RECARGA] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao processar recarga no servidor.");
    }
});


// ============================================================================
// ============================================================================
// 14. 💰 FUNDAÇÃO FINANCEIRA: PAGAR CONVOCAÇÃO DE JOGO (V2 Callable) — HARDENED
// ============================================================================
// Regras:
// - Só o contratante dono do jogo pode pagar
// - valorCentavos tem de ser inteiro positivo
// - IdempotencyKey obrigatória (UUID do cliente) → ID do ledger
// - Jogo não pode estar em estado terminal
// - Congela pagoEmCentavos + valorGoleiroCentavos no documento do jogo
// - Saldo só em carteiras/{uid}.saldoCentavos
// ============================================================================
exports.pagarJogo = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");
    }

    const idJogo = request.data?.idJogo;
    const valorCentavosRaw = request.data?.valorCentavos;
    const idempotencyKey = request.data?.idempotencyKey;

    // --- Validação de entrada (antes da transaction) ---
    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const valorCentavos = Number(valorCentavosRaw);
    if (!Number.isFinite(valorCentavos) || !Number.isInteger(valorCentavos) || valorCentavos <= 0) {
        throw new HttpsError("invalid-argument", "valorCentavos deve ser um inteiro positivo (centavos).");
    }
    // Proteção anti-abuso (teto alto, mas evita overflow acidental)
    if (valorCentavos > 50000000) {
        throw new HttpsError("invalid-argument", "valorCentavos acima do limite permitido.");
    }

    const db = admin.firestore();
    const carteiraRef = db.collection("carteiras").doc(uid);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);
    const jogoRef = db.collection("jogos").doc(idJogo);

    const ESTADOS_BLOQUEADOS = new Set([
        "cancelado",
        "expirado",
        "finalizado",
        "contestado_aceito",
    ]);

    try {
        return await db.runTransaction(async (transaction) => {
            // 1) Idempotência: se já existe ledger com esta key, devolve sucesso sem cobrar de novo
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                const prev = ledgerSnap.data();
                console.log(`[PAGAR_JOGO] Duplicado ignorado: ${idempotencyKey}`);
                return {
                    sucesso: true,
                    mensagem: "Pagamento já processado.",
                    novoSaldoCentavos: prev.saldoAposCentavos ?? null,
                    jaProcessado: true,
                };
            }

            // 2) Jogo — ownership + status
            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) {
                throw new HttpsError("not-found", "Jogo não encontrado.");
            }

            const jogo = jogoSnap.data();

            if (jogo.idContratante !== uid) {
                throw new HttpsError("permission-denied", "Só o contratante dono do jogo pode pagar.");
            }

            const statusAtual = (jogo.status || "").toString();
            if (ESTADOS_BLOQUEADOS.has(statusAtual)) {
                throw new HttpsError(
                    "failed-precondition",
                    `Não é possível pagar um jogo com status "${statusAtual}".`
                );
            }

            // Já pago: evita recobrar o mesmo montante (edições com diferença ainda passam se valor > já pago)
            const jaPagoCentavos = typeof jogo.pagoEmCentavos === "number" ? jogo.pagoEmCentavos : 0;
            if (jogo.statusPagamento === "pago" && valorCentavos <= jaPagoCentavos) {
                return {
                    sucesso: true,
                    mensagem: "Jogo já pago.",
                    novoSaldoCentavos: null,
                    jaProcessado: true,
                };
            }

            // 3) Carteira
            const carteiraSnap = await transaction.get(carteiraRef);
            const saldoAtual = carteiraSnap.exists ? (carteiraSnap.data().saldoCentavos || 0) : 0;

            if (saldoAtual < valorCentavos) {
                throw new HttpsError(
                    "failed-precondition",
                    "Saldo insuficiente. Por favor, recarregue a carteira."
                );
            }

            const novoSaldo = saldoAtual - valorCentavos;
            const novoPagoEmCentavos = jaPagoCentavos + valorCentavos;

            // Congelar repasse do goleiro em centavos (para o robô de pagamento automático)
            let valorGoleiroCentavos = null;
            if (typeof jogo.valorGoleiroCentavos === "number") {
                valorGoleiroCentavos = Math.round(jogo.valorGoleiroCentavos);
            } else if (typeof jogo.valorGoleiro === "number") {
                valorGoleiroCentavos = Math.round(jogo.valorGoleiro * 100);
            } else if (typeof jogo.taxaAplicada === "number" && typeof jogo.valor === "number") {
                valorGoleiroCentavos = Math.max(
                    0,
                    Math.round(jogo.valor * 100) - Math.round(jogo.taxaAplicada * 100)
                );
            }

            // 4) Debita carteira
            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            // 5) Ledger imutável
            transaction.set(ledgerRef, {
                tipo: "pagamento_jogo",
                uid: uid,
                idJogo: idJogo,
                valorCentavos: valorCentavos,
                saldoAposCentavos: novoSaldo,
                idempotencyKey: idempotencyKey,
                descricao: `Pagamento de convocação (${jogo.local || idJogo})`,
                origem: "pagarJogo",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            // 6) Congela valores no jogo
            const updateJogo = {
                pagoEmCentavos: novoPagoEmCentavos,
                statusPagamento: "pago",
                pagoEm: admin.firestore.FieldValue.serverTimestamp(),
            };
            if (valorGoleiroCentavos !== null) {
                updateJogo.valorGoleiroCentavos = valorGoleiroCentavos;
            }
            if (typeof jogo.taxaAplicada === "number") {
                updateJogo.taxaAplicadaCentavos = Math.round(jogo.taxaAplicada * 100);
            }

            transaction.set(jogoRef, updateJogo, { merge: true });

            console.log(
                `[PAGAR_JOGO] uid=${uid} jogo=${idJogo} cobrado=${valorCentavos} saldoApos=${novoSaldo}`
            );

            return {
                sucesso: true,
                novoSaldoCentavos: novoSaldo,
                pagoEmCentavos: novoPagoEmCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[PAGAR_JOGO] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao processar pagamento no servidor.");
    }
});

// ============================================================================
// 15. 💰 SOLICITAR SAQUE (V2 Callable) — Passo 2.1
// ============================================================================
// Cliente só pede. Servidor:
// - valida PIX no perfil
// - valida saldo em carteiras (centavos)
// - debita carteira
// - cria saques/{id} status=pendente
// - grava ledger saque_solicitado com idempotencyKey do cliente
// ============================================================================
exports.solicitarSaque = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");
    }

    const valorCentavosRaw = request.data?.valorCentavos;
    const idempotencyKey = request.data?.idempotencyKey;

    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const valorCentavos = Number(valorCentavosRaw);
    if (!Number.isFinite(valorCentavos) || !Number.isInteger(valorCentavos) || valorCentavos <= 0) {
        throw new HttpsError("invalid-argument", "valorCentavos deve ser um inteiro positivo (centavos).");
    }

    const MIN_SAQUE = 100; // R$ 1,00 — ajusta se quiseres mínimo maior
    const MAX_SAQUE = 500000; // R$ 5.000,00
    if (valorCentavos < MIN_SAQUE) {
        throw new HttpsError("invalid-argument", "Valor mínimo de saque: R$ 1,00.");
    }
    if (valorCentavos > MAX_SAQUE) {
        throw new HttpsError("invalid-argument", "Valor máximo de saque: R$ 5.000,00.");
    }

    const db = admin.firestore();
    const userRef = db.collection("usuarios").doc(uid);
    const carteiraRef = db.collection("carteiras").doc(uid);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);

    try {
        // PIX fora da transaction de escrita financeira (read-only)
        const userSnap = await userRef.get();
        if (!userSnap.exists) {
            throw new HttpsError("failed-precondition", "Perfil de utilizador não encontrado.");
        }
        const userData = userSnap.data();
        const chavePix = (userData.chavePix || "").toString().trim();
        const tipoPix = (userData.tipoPix || "").toString().trim();
        const nome = (userData.nome || "Goleiro").toString();

        if (!chavePix) {
            throw new HttpsError(
                "failed-precondition",
                "Cadastre sua chave PIX no perfil antes de solicitar saque."
            );
        }

        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                const prev = ledgerSnap.data();
                console.log(`[SAQUE] Duplicado ignorado: ${idempotencyKey}`);
                return {
                    sucesso: true,
                    mensagem: "Saque já processado.",
                    idSaque: prev.idSaque || null,
                    novoSaldoCentavos: prev.saldoAposCentavos ?? null,
                    jaProcessado: true,
                };
            }

            const carteiraSnap = await transaction.get(carteiraRef);
            const carteira = carteiraSnap.exists ? carteiraSnap.data() : {};
            const saldoAtual = carteira.saldoCentavos || 0;
            const retido = carteira.retidoCentavos || 0;
            const disponivel = saldoAtual - retido;

            if (disponivel < valorCentavos) {
                throw new HttpsError(
                    "failed-precondition",
                    "Saldo insuficiente para este saque."
                );
            }

            const novoSaldo = saldoAtual - valorCentavos;
            const saqueRef = db.collection("saques").doc();

            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            transaction.set(saqueRef, {
                id: saqueRef.id,
                idGoleiro: uid,
                nomeGoleiro: nome,
                chavePix: chavePix,
                tipoPix: tipoPix || null,
                valorCentavos: valorCentavos,
                // legado UI admin (R$)
                valor: valorCentavos / 100,
                status: "pendente",
                idempotencyKey: idempotencyKey,
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.set(ledgerRef, {
                tipo: "saque_solicitado",
                uid: uid,
                idSaque: saqueRef.id,
                valorCentavos: valorCentavos,
                saldoAposCentavos: novoSaldo,
                idempotencyKey: idempotencyKey,
                descricao: `Saque PIX solicitado (${chavePix})`,
                origem: "solicitarSaque",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`[SAQUE] uid=${uid} saque=${saqueRef.id} -${valorCentavos} → saldo=${novoSaldo}`);

            return {
                sucesso: true,
                idSaque: saqueRef.id,
                novoSaldoCentavos: novoSaldo,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[SAQUE] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao processar solicitação de saque.");
    }
});

// ============================================================================
// 16. 🚪 PROCESSAR DESISTÊNCIA DO GOLEIRO (V2 Callable) — Passo 2.2
// ============================================================================
// - Só o goleiro designado pode desistir
// - Multa calculada no servidor via configuracoes/global
// - Multa → carteiras.multasPendentesCentavos + ledger
// - Jogo volta a aberto; recibo cancelado_{jogoId}_{uid}
// ============================================================================
exports.processarDesistenciaGoleiro = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    const idempotencyKey = request.data?.idempotencyKey;

    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const db = admin.firestore();

    let horasRegraMulta = 12;
    let valorMultaReais = 10.0;
    try {
        const configDoc = await db.collection("configuracoes").doc("global").get();
        if (configDoc.exists) {
            const conf = configDoc.data();
            horasRegraMulta = conf.horasMultaCancelamento ?? 12;
            valorMultaReais = conf.valorMultaCancelamento ?? 10.0;
        }
    } catch (e) {
        console.error("[DESISTENCIA] Falha ao ler config:", e);
    }

    const jogoRef = db.collection("jogos").doc(idJogo);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);
    const carteiraRef = db.collection("carteiras").doc(uid);
    const goleiroRef = db.collection("usuarios").doc(uid);

    try {
        return await db.runTransaction(async (transaction) => {
            // ===== LEITURAS =====
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                return {
                    sucesso: true,
                    mensagem: "Desistência já processada.",
                    jaProcessado: true,
                    multaCentavos: ledgerSnap.data().valorCentavos || 0,
                };
            }

            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) throw new HttpsError("not-found", "Jogo não encontrado.");

            const jogo = jogoSnap.data();

            if (jogo.idGoleiro !== uid) {
                throw new HttpsError("permission-denied", "Só o goleiro designado pode desistir.");
            }

            const statusAtual = (jogo.status || "").toString();
            if (!["fechado", "aberto"].includes(statusAtual)) {
                throw new HttpsError(
                    "failed-precondition",
                    `Não é possível desistir com status "${statusAtual}".`
                );
            }

            let multaCentavos = 0;
            if (jogo.dataHora) {
                const dataJogo = jogo.dataHora.toDate();
                const diffHoras = (dataJogo.getTime() - Date.now()) / 3600000;
                if (diffHoras < horasRegraMulta) {
                    multaCentavos = Math.round(Number(valorMultaReais) * 100);
                }
            }

            let multasAtuais = 0;
            if (multaCentavos > 0) {
                const carteiraSnap = await transaction.get(carteiraRef);
                multasAtuais = carteiraSnap.exists
                    ? (carteiraSnap.data().multasPendentesCentavos || 0)
                    : 0;
            }

            // ===== ESCRITAS =====
            transaction.update(jogoRef, {
                idGoleiro: admin.firestore.FieldValue.delete(),
                nomeGoleiro: admin.firestore.FieldValue.delete(),
                status: "aberto",
                desistenciaEm: admin.firestore.FieldValue.serverTimestamp(),
                desistenciaPor: uid,
                desistentes: admin.firestore.FieldValue.arrayUnion([uid]),
                editadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            const idRecibo = `cancelado_${idJogo}_${uid}`;
            const reciboRef = db.collection("jogos").doc(idRecibo);
            transaction.set(reciboRef, {
                ...jogo,
                id: idRecibo,
                status: "cancelado",
                canceladoPor: "goleiro",
                idGoleiro: uid,
                arquivadoGoleiro: true,
                motivoCancelamento: "Você desistiu desta partida.",
                dataCancelamento: admin.firestore.FieldValue.serverTimestamp(),
                multaCentavos: multaCentavos,
            });

            if (multaCentavos > 0) {
                transaction.set(carteiraRef, {
                    multasPendentesCentavos: multasAtuais + multaCentavos,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }

            transaction.set(goleiroRef, {
                faltas: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            transaction.set(ledgerRef, {
                tipo: "multa_desistencia",
                uid: uid,
                idJogo: idJogo,
                valorCentavos: multaCentavos,
                idempotencyKey: idempotencyKey,
                descricao: multaCentavos > 0
                    ? `Multa por desistência (< ${horasRegraMulta}h)`
                    : "Desistência sem multa",
                origem: "processarDesistenciaGoleiro",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (jogo.idContratante) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: jogo.idContratante,
                    titulo: "Atenção: Goleiro Desistiu!",
                    mensagem: "O goleiro cancelou a participação. A partida voltou para o mural!",
                    tipo: "goleiro_desistiu",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`[DESISTENCIA] jogo=${idJogo} uid=${uid} multa=${multaCentavos}`);

            return {
                sucesso: true,
                multaCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[DESISTENCIA] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao processar desistência.");
    }
});


exports.processarContestacao = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    const acao = (request.data?.acao || "").toString().toLowerCase();
    const idempotencyKey = request.data?.idempotencyKey;
    const respostaTexto = (request.data?.respostaTexto || "").toString().slice(0, 1000);

    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!["aceitar", "recusar"].includes(acao)) {
        throw new HttpsError("invalid-argument", 'acao deve ser "aceitar" ou "recusar".');
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const db = admin.firestore();
    const jogoRef = db.collection("jogos").doc(idJogo);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);

    try {
        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                return {
                    sucesso: true,
                    mensagem: "Contestação já processada.",
                    jaProcessado: true,
                };
            }

            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) throw new HttpsError("not-found", "Jogo não encontrado.");

            const jogo = jogoSnap.data();

            if (jogo.idGoleiro !== uid) {
                throw new HttpsError("permission-denied", "Só o goleiro do jogo pode responder à contestação.");
            }

            if ((jogo.status || "") !== "contestado") {
                throw new HttpsError(
                    "failed-precondition",
                    `Jogo não está em contestação (status: ${jogo.status}).`
                );
            }

            if (acao === "aceitar") {
                if (!validarTransicao("contestado", "contestado_aceito")) {
                    throw new HttpsError("failed-precondition", "Transição de status inválida.");
                }

                // Valor a estornar: preferir pagoEmCentavos
                let estornoCentavos = 0;
                if (typeof jogo.pagoEmCentavos === "number" && jogo.pagoEmCentavos > 0) {
                    estornoCentavos = Math.round(jogo.pagoEmCentavos);
                } else if (typeof jogo.valor === "number") {
                    estornoCentavos = Math.round(jogo.valor * 100);
                }

                const idContratante = jogo.idContratante;
                if (!idContratante) {
                    throw new HttpsError("failed-precondition", "Jogo sem contratante.");
                }

                const carteiraContratanteRef = db.collection("carteiras").doc(idContratante);
                const carteiraSnap = await transaction.get(carteiraContratanteRef);
                const saldoAtual = carteiraSnap.exists
                    ? (carteiraSnap.data().saldoCentavos || 0)
                    : 0;
                const novoSaldo = saldoAtual + estornoCentavos;

                if (estornoCentavos > 0) {
                    transaction.set(carteiraContratanteRef, {
                        saldoCentavos: novoSaldo,
                        atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }

                transaction.update(jogoRef, {
                    status: "contestado_aceito",
                    "contestacao.statusMediacao": "resolvido_goleiro_aceitou",
                    "contestacao.finalizadoEm": admin.firestore.FieldValue.serverTimestamp(),
                    "contestacao.respostaGoleiro": respostaTexto || "Aceite pelo goleiro",
                });

                // Falta no goleiro
                const goleiroRef = db.collection("usuarios").doc(uid);
                transaction.set(goleiroRef, {
                    faltas: admin.firestore.FieldValue.increment(1),
                }, { merge: true });

                transaction.set(ledgerRef, {
                    tipo: "estorno_contestacao",
                    uid: idContratante,
                    idJogo: idJogo,
                    idGoleiro: uid,
                    valorCentavos: estornoCentavos,
                    saldoAposCentavos: novoSaldo,
                    idempotencyKey: idempotencyKey,
                    descricao: "Estorno: contestação aceita pelo goleiro",
                    origem: "processarContestacao",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });

                // Notifica contratante
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: idContratante,
                    titulo: "Contestação aceita",
                    mensagem: `O goleiro aceitou a contestação. R$ ${(estornoCentavos / 100).toFixed(2).replace(".", ",")} voltaram à sua carteira.`,
                    tipo: "contestacao_aceita",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });

                console.log(`[CONTESTACAO] ACEITAR jogo=${idJogo} estorno=${estornoCentavos}`);

                return {
                    sucesso: true,
                    acao: "aceitar",
                    estornoCentavos,
                    jaProcessado: false,
                };
            }

            // --- recusar ---
            transaction.update(jogoRef, {
                "contestacao.statusMediacao": "em_analise_suporte",
                "contestacao.respostaGoleiro": respostaTexto || "Recusado pelo goleiro",
                "contestacao.respondidoEm": admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.set(ledgerRef, {
                tipo: "contestacao_recusada",
                uid: uid,
                idJogo: idJogo,
                valorCentavos: 0,
                idempotencyKey: idempotencyKey,
                descricao: "Goleiro recusou contestação — em análise suporte",
                origem: "processarContestacao",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (jogo.idContratante) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: jogo.idContratante,
                    titulo: "Contestação em análise",
                    mensagem: "O goleiro contestou os fatos. Nossa equipa irá analisar.",
                    tipo: "contestacao_recusada",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`[CONTESTACAO] RECUSAR jogo=${idJogo}`);

            return {
                sucesso: true,
                acao: "recusar",
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[CONTESTACAO] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao processar contestação.");
    }
});

// ============================================================================
// 18. ⚽ CRIAR E PAGAR JOGO (V2 Callable) — Passo 2.4 ATÓMICO
// ============================================================================
// Cria (ou atualiza) o jogo e debita a carteira na MESMA transaction.
// Elimina jogo órfão com statusPagamento pendente.
// ============================================================================
exports.criarEPagarJogo = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const data = request.data || {};
    const idempotencyKey = data.idempotencyKey;
    const jogoPayload = data.jogo; // objeto com campos do jogo
    const idJogoExistente = data.idJogo || null; // edição

    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }
    if (!jogoPayload || typeof jogoPayload !== "object") {
        throw new HttpsError("invalid-argument", "Payload do jogo inválido.");
    }

    // Campos mínimos
    const local = (jogoPayload.local || "").toString();
    const valorReais = Number(jogoPayload.valor);
    const nivelGoleiro = (jogoPayload.nivelGoleiro || "").toString();
    const duracao = Number(jogoPayload.duracao) || 60;

    if (!local) throw new HttpsError("invalid-argument", "Local obrigatório.");
    if (!Number.isFinite(valorReais) || valorReais <= 0) {
        throw new HttpsError("invalid-argument", "Valor do jogo inválido.");
    }

    const valorTotalCentavos = Math.round(valorReais * 100);
    if (valorTotalCentavos <= 0) {
        throw new HttpsError("invalid-argument", "Valor em centavos inválido.");
    }

    // Taxas / valor goleiro (podem vir do cliente já calculados; servidor confirma)
    let taxaAplicadaCentavos = 0;
    if (typeof jogoPayload.taxaAplicadaCentavos === "number") {
        taxaAplicadaCentavos = Math.round(jogoPayload.taxaAplicadaCentavos);
    } else if (typeof jogoPayload.taxaAplicada === "number") {
        taxaAplicadaCentavos = Math.round(jogoPayload.taxaAplicada * 100);
    }

    let valorGoleiroCentavos = 0;
    if (typeof jogoPayload.valorGoleiroCentavos === "number") {
        valorGoleiroCentavos = Math.round(jogoPayload.valorGoleiroCentavos);
    } else if (typeof jogoPayload.valorGoleiro === "number") {
        valorGoleiroCentavos = Math.round(jogoPayload.valorGoleiro * 100);
    } else {
        valorGoleiroCentavos = Math.max(0, valorTotalCentavos - taxaAplicadaCentavos);
    }

    const db = admin.firestore();
    const carteiraRef = db.collection("carteiras").doc(uid);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);
    const jogoRef = idJogoExistente
        ? db.collection("jogos").doc(idJogoExistente)
        : db.collection("jogos").doc();

    try {
        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                const prev = ledgerSnap.data();
                return {
                    sucesso: true,
                    mensagem: "Operação já processada.",
                    idJogo: prev.idJogo || jogoRef.id,
                    novoSaldoCentavos: prev.saldoAposCentavos ?? null,
                    jaProcessado: true,
                };
            }

            let jaPagoCentavos = 0;
            let statusAtual = "aberto";

            if (idJogoExistente) {
                const jogoSnap = await transaction.get(jogoRef);
                if (!jogoSnap.exists) {
                    throw new HttpsError("not-found", "Jogo a editar não encontrado.");
                }
                const jogoAtual = jogoSnap.data();
                if (jogoAtual.idContratante !== uid) {
                    throw new HttpsError("permission-denied", "Só o dono pode editar este jogo.");
                }
                const statusNorm = (jogoAtual.status || "").toString().toLowerCase();
                const terminais = ["cancelado", "expirado", "finalizado", "contestado_aceito"];
                if (terminais.includes(statusNorm)) {
                    throw new HttpsError(
                        "failed-precondition",
                        `Jogo com status ${statusNorm} não pode ser editado.`
                    );
                }
                // Priorizar pagoEmCentavos; fallback legado em valor (reais)
                if (typeof jogoAtual.pagoEmCentavos === "number") {
                    jaPagoCentavos = Math.round(jogoAtual.pagoEmCentavos);
                } else if (typeof jogoAtual.valorCentavos === "number") {
                    jaPagoCentavos = Math.round(jogoAtual.valorCentavos);
                } else if (typeof jogoAtual.valor === "number") {
                    jaPagoCentavos = Math.round(jogoAtual.valor * 100);
                } else {
                    jaPagoCentavos = 0;
                }
                statusAtual = statusNorm || "aberto";
            }

            // Delta financeiro na edição de nível/duração/preço:
            //   > 0 → cobra diferença (upgrade Livre→Elite)
            //   < 0 → estorna diferença (downgrade Elite→Livre)
            //   = 0 → só atualiza dados do jogo
            const deltaCentavos = valorTotalCentavos - jaPagoCentavos;
            const aCobrarCentavos = Math.max(0, deltaCentavos);
            const aEstornarCentavos = Math.max(0, -deltaCentavos);

            const carteiraSnap = await transaction.get(carteiraRef);
            const saldoAtual = carteiraSnap.exists ? (carteiraSnap.data().saldoCentavos || 0) : 0;

            if (aCobrarCentavos > 0 && saldoAtual < aCobrarCentavos) {
                throw new HttpsError(
                    "failed-precondition",
                    "Saldo insuficiente. Por favor, recarregue a carteira."
                );
            }

            const novoSaldo = saldoAtual - aCobrarCentavos + aEstornarCentavos;
            // pagoEmCentavos = preço ATUAL do jogo (não acumula upgrades sem estornar downgrades)
            const novoPagoEmCentavos = valorTotalCentavos;

            // Montar documento do jogo
            // Preferir epoch ms (fuso-agnóstico). ISO sem Z no Node vira UTC e atrasa/adia o jogo.
            let dataHora = null;
            if (typeof jogoPayload.dataHoraMs === "number") {
                dataHora = admin.firestore.Timestamp.fromMillis(jogoPayload.dataHoraMs);
            } else if (jogoPayload.dataHora) {
                if (jogoPayload.dataHora._seconds) {
                    dataHora = admin.firestore.Timestamp.fromMillis(jogoPayload.dataHora._seconds * 1000);
                } else {
                    dataHora = admin.firestore.Timestamp.fromDate(new Date(jogoPayload.dataHora));
                }
            }

            let dataHoraFim = null;
            if (typeof jogoPayload.dataHoraFimMs === "number") {
                dataHoraFim = admin.firestore.Timestamp.fromMillis(jogoPayload.dataHoraFimMs);
            } else if (jogoPayload.dataHoraFim) {
                if (jogoPayload.dataHoraFim._seconds) {
                    dataHoraFim = admin.firestore.Timestamp.fromMillis(jogoPayload.dataHoraFim._seconds * 1000);
                } else {
                    dataHoraFim = admin.firestore.Timestamp.fromDate(new Date(jogoPayload.dataHoraFim));
                }
            }

            const jogoDoc = {
                id: jogoRef.id,
                idContratante: uid,
                local: local,
                valor: valorReais,
                valorCentavos: valorTotalCentavos,
                nivelGoleiro: nivelGoleiro,
                tipoQuadra: jogoPayload.tipoQuadra || "",
                duracao: duracao,
                observacoes: jogoPayload.observacoes || "",
                // NUNCA ressuscitar jogo cancelado/expirado/finalizado.
                // Só mantém fechado se já estava fechado; senão aberto (criação/edição válida).
                status: (statusAtual === "fechado")
                    ? "fechado"
                    : (["cancelado", "expirado", "finalizado", "contestado_aceito"].includes(statusAtual)
                        ? statusAtual
                        : "aberto"),
                statusPagamento: novoPagoEmCentavos >= valorTotalCentavos ? "pago" : "pendente",
                pagoEmCentavos: novoPagoEmCentavos,
                ativoNoMural: !["cancelado", "expirado", "finalizado", "contestado_aceito"].includes(statusAtual),
                valorGoleiro: valorGoleiroCentavos / 100,
                valorGoleiroCentavos: valorGoleiroCentavos,
                taxaAplicada: taxaAplicadaCentavos / 100,
                taxaAplicadaCentavos: taxaAplicadaCentavos,
                dataExibicao: jogoPayload.dataExibicao || "",
                horaExibicao: jogoPayload.horaExibicao || "",
                editadoEm: admin.firestore.FieldValue.serverTimestamp(),
            };

            if (dataHora) jogoDoc.dataHora = dataHora;
            if (dataHoraFim) jogoDoc.dataHoraFim = dataHoraFim;
            if (jogoPayload.latitude != null) jogoDoc.latitude = jogoPayload.latitude;
            if (jogoPayload.longitude != null) jogoDoc.longitude = jogoPayload.longitude;
            if (jogoPayload.latitude != null && jogoPayload.longitude != null) {
                jogoDoc.localizacao = new admin.firestore.GeoPoint(
                    Number(jogoPayload.latitude),
                    Number(jogoPayload.longitude)
                );
            }
            if (jogoPayload.idQuadra) jogoDoc.idQuadra = jogoPayload.idQuadra;
            if (!idJogoExistente) {
                jogoDoc.criadoEm = admin.firestore.FieldValue.serverTimestamp();
            }
            if (aCobrarCentavos > 0 || aEstornarCentavos > 0) {
                jogoDoc.pagoEm = admin.firestore.FieldValue.serverTimestamp();
            }

            transaction.set(jogoRef, jogoDoc, { merge: true });

            if (aCobrarCentavos > 0 || aEstornarCentavos > 0) {
                transaction.set(carteiraRef, {
                    saldoCentavos: novoSaldo,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }

            let tipoLedger = "edicao_jogo_sem_movimento";
            let valorLedger = 0;
            let descricaoLedger = idJogoExistente
                ? `Edição de convocação sem alteração de valor (${local})`
                : `Criação e pagamento de convocação (${local})`;

            if (aCobrarCentavos > 0) {
                tipoLedger = idJogoExistente ? "ajuste_upgrade_jogo" : "pagamento_jogo";
                valorLedger = aCobrarCentavos;
                descricaoLedger = idJogoExistente
                    ? `Upgrade de nível/preço (+R$ ${(aCobrarCentavos / 100).toFixed(2)}) — ${local}`
                    : `Criação e pagamento de convocação (${local})`;
            } else if (aEstornarCentavos > 0) {
                tipoLedger = "estorno_downgrade_jogo";
                valorLedger = aEstornarCentavos;
                descricaoLedger = `Downgrade de nível/preço (−R$ ${(aEstornarCentavos / 100).toFixed(2)}) — ${local}`;
            }

            transaction.set(ledgerRef, {
                tipo: tipoLedger,
                uid: uid,
                idJogo: jogoRef.id,
                valorCentavos: valorLedger,
                deltaCentavos: deltaCentavos,
                cobradoCentavos: aCobrarCentavos,
                estornadoCentavos: aEstornarCentavos,
                saldoAposCentavos: (aCobrarCentavos > 0 || aEstornarCentavos > 0) ? novoSaldo : saldoAtual,
                idempotencyKey: idempotencyKey,
                descricao: descricaoLedger,
                origem: "criarEPagarJogo",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(
                `[CRIAR_PAGAR] uid=${uid} jogo=${jogoRef.id} cobrar=${aCobrarCentavos} estornar=${aEstornarCentavos} saldoApos=${novoSaldo}`
            );

            return {
                sucesso: true,
                idJogo: jogoRef.id,
                novoSaldoCentavos: (aCobrarCentavos > 0 || aEstornarCentavos > 0) ? novoSaldo : saldoAtual,
                pagoEmCentavos: novoPagoEmCentavos,
                cobradoCentavos: aCobrarCentavos,
                estornadoCentavos: aEstornarCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[CRIAR_PAGAR] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao criar/pagar jogo.");
    }
});

// ============================================================================
// 19. ✅ FINALIZAR JOGO / PAGAR GOLEIRO (V2 Callable) — Contratante
// ============================================================================
// Disparado após avaliação positiva. Credita carteira do goleiro + finaliza jogo.
// Idempotente: ledger recebimento_{jogoId}
// ============================================================================
exports.finalizarJogoContratante = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    const idempotencyKey = request.data?.idempotencyKey;

    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const db = admin.firestore();
    const jogoRef = db.collection("jogos").doc(idJogo);
    // Chave estável partilhada com o robô de pagamento automático
    const ledgerRef = db.collection("ledger").doc(`recebimento_${idJogo}`);

    try {
        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                return {
                    sucesso: true,
                    mensagem: "Pagamento já processado.",
                    jaProcessado: true,
                    valorPagoCentavos: ledgerSnap.data().valorCentavos || 0,
                };
            }

            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) throw new HttpsError("not-found", "Jogo não encontrado.");

            const jogo = jogoSnap.data();
            if (jogo.idContratante !== uid) {
                throw new HttpsError("permission-denied", "Só o contratante dono pode finalizar.");
            }

            const status = (jogo.status || "").toString();
            if (status === "finalizado") {
                return { sucesso: true, mensagem: "Já finalizado.", jaProcessado: true };
            }
            if (status === "contestado" || status === "contestado_aceito") {
                throw new HttpsError("failed-precondition", "Jogo em contestação não pode ser pago por aqui.");
            }
            if (status === "cancelado" || status === "expirado") {
                throw new HttpsError("failed-precondition", `Jogo com status ${status} não pode ser finalizado.`);
            }
            if (!jogo.idGoleiro) {
                throw new HttpsError("failed-precondition", "Jogo sem goleiro designado.");
            }
            if (!validarTransicao(status, "finalizado") && status !== "fechado") {
                // permite fechado→finalizado; se status for outro permitido na máquina
                if (status !== "fechado") {
                    throw new HttpsError("failed-precondition", `Transição ${status}→finalizado inválida.`);
                }
            }

            // Repasse em centavos
            let valorRepasseCentavos = 0;
            if (typeof jogo.valorGoleiroCentavos === "number") {
                valorRepasseCentavos = Math.round(jogo.valorGoleiroCentavos);
            } else if (typeof jogo.valorGoleiro === "number") {
                valorRepasseCentavos = Math.round(jogo.valorGoleiro * 100);
            } else if (typeof jogo.pagoEmCentavos === "number" && typeof jogo.taxaAplicadaCentavos === "number") {
                valorRepasseCentavos = Math.max(0, Math.round(jogo.pagoEmCentavos) - Math.round(jogo.taxaAplicadaCentavos));
            } else if (typeof jogo.valor === "number") {
                valorRepasseCentavos = Math.max(0, Math.round(jogo.valor * 100));
            }

            const idGoleiro = jogo.idGoleiro;
            const carteiraRef = db.collection("carteiras").doc(idGoleiro);
            const cSnap = await transaction.get(carteiraRef);
            const saldoAtual = cSnap.exists ? (cSnap.data().saldoCentavos || 0) : 0;
            const novoSaldo = saldoAtual + valorRepasseCentavos;

            transaction.set(carteiraRef, {
                saldoCentavos: novoSaldo,
                atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            transaction.set(ledgerRef, {
                tipo: "recebimento_jogo",
                uid: idGoleiro,
                idJogo: idJogo,
                valorCentavos: valorRepasseCentavos,
                saldoAposCentavos: novoSaldo,
                idempotencyKey: `recebimento_${idJogo}`,
                descricao: `Recebimento: ${jogo.local || "Pelada"}`,
                origem: "finalizarJogoContratante",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.update(jogoRef, {
                status: "finalizado",
                pagoEm: admin.firestore.FieldValue.serverTimestamp(),
                finalizadoPorContratante: true,
                valorPagoAoGoleiroCentavos: valorRepasseCentavos,
                valorPagoAoGoleiro: valorRepasseCentavos / 100,
            });

            const goleiroRef = db.collection("usuarios").doc(idGoleiro);
            transaction.set(goleiroRef, {
                totalGanhosCentavos: admin.firestore.FieldValue.increment(valorRepasseCentavos),
                atuadas: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            // Stats do contratante (perfil: JOGOS + TOTAL INVESTIDO)
            const valorCobradoCentavos = typeof jogo.pagoEmCentavos === "number"
                ? Math.round(jogo.pagoEmCentavos)
                : (typeof jogo.valor === "number" ? Math.round(jogo.valor * 100) : 0);
            transaction.set(db.collection("usuarios").doc(uid), {
                jogosRealizados: admin.firestore.FieldValue.increment(1),
                partidasOrganizadas: admin.firestore.FieldValue.increment(1),
                totalGastosCentavos: admin.firestore.FieldValue.increment(valorCobradoCentavos),
                totalGastos: admin.firestore.FieldValue.increment(valorCobradoCentavos / 100),
            }, { merge: true });

            const pushRef = db.collection("notificacoes").doc();
            transaction.set(pushRef, {
                idUsuario: idGoleiro,
                titulo: "Pagamento Liberado! 💰",
                mensagem: `R$ ${(valorRepasseCentavos / 100).toFixed(2).replace(".", ",")} do jogo em ${jogo.local || "sua arena"} já estão na sua carteira.`,
                tipo: "recebimento_jogo",
                idJogo: idJogo,
                lida: false,
                data: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`[FINALIZAR] jogo=${idJogo} goleiro=${idGoleiro} +${valorRepasseCentavos}`);

            return {
                sucesso: true,
                valorPagoCentavos: valorRepasseCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[FINALIZAR] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao finalizar jogo.");
    }
});

// ============================================================================
// 20. 🚫 CANCELAR JOGO PELO CONTRATANTE (V2 Callable)
// ============================================================================
// Estorna pagoEmCentavos - multa (se aplicável) para carteiras do contratante.
// ============================================================================
exports.cancelarJogoContratante = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    const motivo = (request.data?.motivo || "Cancelado pelo contratante").toString().slice(0, 300);
    const idempotencyKey = request.data?.idempotencyKey;

    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const db = admin.firestore();

    let horasRegraMulta = 12;
    let valorMultaReais = 10.0;
    try {
        const configDoc = await db.collection("configuracoes").doc("global").get();
        if (configDoc.exists) {
            const conf = configDoc.data();
            horasRegraMulta = conf.horasMultaCancelamento ?? 12;
            valorMultaReais = conf.valorMultaCancelamento ?? 10.0;
        }
    } catch (e) {
        console.error("[CANCELAR] config:", e);
    }

    const jogoRef = db.collection("jogos").doc(idJogo);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);
    const carteiraRef = db.collection("carteiras").doc(uid);
    const userRef = db.collection("usuarios").doc(uid);

    try {
        return await db.runTransaction(async (transaction) => {
            // ===== TODAS AS LEITURAS PRIMEIRO (regra Firestore) =====
            const ledgerSnap = await transaction.get(ledgerRef);
            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) {
                throw new HttpsError("not-found", "Jogo não encontrado.");
            }

            const jogo = jogoSnap.data();
            if (jogo.idContratante !== uid) {
                throw new HttpsError("permission-denied", "Só o contratante dono pode cancelar.");
            }

            const status = (jogo.status || "").toString().toLowerCase();

            // Idempotência: ledger já existe — garante status cancelado (auto-cura se ficou aberto)
            if (ledgerSnap.exists) {
                if (status !== "cancelado") {
                    transaction.set(jogoRef, {
                        status: "cancelado",
                        canceladoPor: "contratante",
                        ativoNoMural: false,
                        idGoleiro: admin.firestore.FieldValue.delete(),
                        nomeGoleiro: admin.firestore.FieldValue.delete(),
                        editadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }
                return {
                    sucesso: true,
                    mensagem: "Cancelamento já processado.",
                    jaProcessado: true,
                    estornoCentavos: ledgerSnap.data().valorCentavos || 0,
                    multaCentavos: ledgerSnap.data().multaCentavos || 0,
                };
            }

            if (["cancelado", "expirado", "finalizado", "contestado_aceito"].includes(status)) {
                throw new HttpsError("failed-precondition", `Jogo já está ${status}.`);
            }

            // Multa se faltam menos de X horas
            let multaCentavos = 0;
            if (jogo.dataHora) {
                const dataJogo = jogo.dataHora.toDate();
                const diffHoras = (dataJogo.getTime() - Date.now()) / 3600000;
                if (diffHoras < horasRegraMulta) {
                    multaCentavos = Math.round(Number(valorMultaReais) * 100);
                }
            }

            let pagoCentavos = 0;
            if (typeof jogo.pagoEmCentavos === "number") {
                pagoCentavos = Math.round(jogo.pagoEmCentavos);
            } else if (jogo.statusPagamento === "pago" && typeof jogo.valor === "number") {
                pagoCentavos = Math.round(jogo.valor * 100);
            }

            const estornoCentavos = Math.max(0, pagoCentavos - multaCentavos);

            // Ler carteira ANTES de qualquer write
            let saldoAtual = 0;
            if (estornoCentavos > 0) {
                const cSnap = await transaction.get(carteiraRef);
                saldoAtual = cSnap.exists ? (cSnap.data().saldoCentavos || 0) : 0;
            }

            const novoSaldo = saldoAtual + estornoCentavos;

            // ===== ESCRITAS =====
            // set+merge garante status cancelado mesmo se o doc tiver campos legados
            transaction.set(jogoRef, {
                status: "cancelado",
                statusPagamento: estornoCentavos > 0 ? "estornado" : "cancelado_sem_estorno",
                canceladoEm: admin.firestore.FieldValue.serverTimestamp(),
                canceladoPor: "contratante",
                motivoCancelamento: motivo,
                multaRetidaCentavos: multaCentavos,
                valorEstornadoCentavos: estornoCentavos,
                // Libera goleiro e tira do mural de "buscar"
                idGoleiro: admin.firestore.FieldValue.delete(),
                nomeGoleiro: admin.firestore.FieldValue.delete(),
                ativoNoMural: false,
                editadoEm: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

            if (estornoCentavos > 0) {
                transaction.set(carteiraRef, {
                    saldoCentavos: novoSaldo,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });

                transaction.set(ledgerRef, {
                    tipo: "estorno_cancelamento",
                    uid: uid,
                    idJogo: idJogo,
                    valorCentavos: estornoCentavos,
                    multaCentavos: multaCentavos,
                    saldoAposCentavos: novoSaldo,
                    idempotencyKey: idempotencyKey,
                    descricao: multaCentavos > 0
                        ? `Reembolso parcial (multa R$ ${(multaCentavos / 100).toFixed(2)})`
                        : `Reembolso integral: ${jogo.local || idJogo}`,
                    origem: "cancelarJogoContratante",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
            } else {
                transaction.set(ledgerRef, {
                    tipo: "cancelamento_sem_estorno",
                    uid: uid,
                    idJogo: idJogo,
                    valorCentavos: 0,
                    multaCentavos: multaCentavos,
                    idempotencyKey: idempotencyKey,
                    descricao: multaCentavos > 0
                        ? `Cancelamento com multa total R$ ${(multaCentavos / 100).toFixed(2)} (sem estorno)`
                        : "Cancelamento sem valor a estornar",
                    origem: "cancelarJogoContratante",
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            transaction.set(userRef, {
                cancelamentos: admin.firestore.FieldValue.increment(1),
            }, { merge: true });

            if (jogo.idGoleiro) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: jogo.idGoleiro,
                    titulo: "Partida cancelada",
                    mensagem: `O contratante cancelou a partida em ${jogo.local || "a arena"}. A sua agenda foi liberada.`,
                    tipo: "jogo_cancelado",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`[CANCELAR] jogo=${idJogo} pago=${pagoCentavos} estorno=${estornoCentavos} multa=${multaCentavos}`);

            return {
                sucesso: true,
                estornoCentavos,
                multaCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[CANCELAR] Erro:", error);
        if (error instanceof HttpsError) throw error;
        // Mensagem mais útil em dev
        const msg = (error && error.message) ? String(error.message) : "Falha ao cancelar jogo.";
        if (msg.includes("reads must be executed before") || msg.includes("READ_AFTER_WRITE")) {
            throw new HttpsError("internal", "Erro interno de transação (leitura/escrita). Tente de novo.");
        }
        throw new HttpsError("internal", "Falha ao cancelar jogo.");
    }
});


exports.aceitarConvocacao = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }

    const db = admin.firestore();
    const jogoRef = db.collection("jogos").doc(idJogo);
    const userRef = db.collection("usuarios").doc(uid);

    try {
        // Leituras fora da transaction (perfil + conflitos de agenda)
        const userSnap = await userRef.get();
        if (!userSnap.exists) {
            throw new HttpsError("failed-precondition", "Perfil não encontrado.");
        }
        const userData = userSnap.data();
        if ((userData.tipoPerfil || "").toString().toLowerCase() !== "goleiro") {
            throw new HttpsError("permission-denied", "Apenas goleiros podem aceitar convocações.");
        }

        const nomeGoleiro = (userData.nome || "Goleiro").toString();
        const categoria = (userData.categoria || "livre").toString().toLowerCase();
        const atuadas = Number(userData.atuadas || userData.jogosRealizados || 0);

        // Nota: preferir notaMedia gravada; senão recalcular (campos oficiais + legado)
        const totalAvaliacoes = Number(userData.totalAvaliacoes || 0);
        const somaNotas = Number(
            userData.somaNotasAvaliacoes != null
                ? userData.somaNotasAvaliacoes
                : (userData.somaAvaliacoes || 0)
        );
        let notaMedia = Number(userData.notaMedia || 0);
        if (totalAvaliacoes > 0 && somaNotas > 0) {
            notaMedia = somaNotas / totalAvaliacoes;
        }

        // Defaults = mesmos do Flutter (configuracoes/global sobrescreve)
        let reqExperientePartidas = 5;
        let reqExperienteNota = 4.2;
        let reqElitePartidas = 15;
        let reqEliteNota = 4.5;
        try {
            const configDoc = await db.collection("configuracoes").doc("global").get();
            if (configDoc.exists) {
                const conf = configDoc.data();
                reqExperientePartidas = conf.reqExperientePartidas ?? reqExperientePartidas;
                reqExperienteNota = conf.reqExperienteNota ?? reqExperienteNota;
                reqElitePartidas = conf.reqElitePartidas ?? reqElitePartidas;
                reqEliteNota = conf.reqEliteNota ?? reqEliteNota;
            }
        } catch (_) { /* defaults */ }

        function rankDe(nivelStr) {
            const n = (nivelStr || "livre").toLowerCase();
            if (n.includes("elite") || n.includes("pared")) return 2;
            if (n.includes("exp") || n.includes("inter") || n.includes("médio") || n.includes("medio")) return 1;
            return 0; // livre / vazio
        }

        function rankGoleiroEfetivo() {
            // max(categoria oficial, métricas atuais) — Elite joga qualquer; Livre só livre
            let rankCat = rankDe(categoria);
            let rankMet = 0;
            if (atuadas >= reqElitePartidas && notaMedia >= reqEliteNota) rankMet = 2;
            else if (atuadas >= reqExperientePartidas && notaMedia >= reqExperienteNota) rankMet = 1;
            return Math.max(rankCat, rankMet);
        }

        // Pré-leitura do jogo para conflitos (fora da tx)
        const jogoPre = await jogoRef.get();
        if (!jogoPre.exists) throw new HttpsError("not-found", "Jogo não encontrado.");
        const jogoPreData = jogoPre.data();

        const statusPre = (jogoPreData.status || "").toString().toLowerCase();
        if (statusPre !== "aberto") {
            throw new HttpsError(
                "failed-precondition",
                statusPre === "cancelado"
                    ? "Esta partida foi cancelada pelo contratante."
                    : "Ops! Outro goleiro foi mais rápido ou a partida não está mais disponível."
            );
        }
        if (jogoPreData.canceladoPor || jogoPreData.ativoNoMural === false) {
            throw new HttpsError("failed-precondition", "Esta partida não está mais disponível.");
        }

        const desistentes = jogoPreData.desistentes || [];
        if (Array.isArray(desistentes) && desistentes.includes(uid)) {
            throw new HttpsError("failed-precondition", "Você já desistiu desta partida e não pode aceitá-la novamente.");
        }

        const nivelExigido = jogoPreData.nivelGoleiro || jogoPreData.nivel || "livre";
        if (rankGoleiroEfetivo() < rankDe(nivelExigido)) {
            throw new HttpsError(
                "failed-precondition",
                "Você não atende aos requisitos de nível para esta partida."
            );
        }

        // Conflito de agenda no mesmo dia
        if (jogoPreData.dataHora) {
            const inicioNovo = jogoPreData.dataHora.toDate();
            const duracaoMinNovo = jogoPreData.duracao || 60;
            const fimNovo = new Date(inicioNovo.getTime() + duracaoMinNovo * 60000);
            const localNovo = (jogoPreData.local || "").toString().trim().toLowerCase();

            const inicioDoDia = new Date(inicioNovo);
            inicioDoDia.setHours(0, 0, 0, 0);
            const fimDoDia = new Date(inicioNovo);
            fimDoDia.setHours(23, 59, 59, 999);

            const conflitosSnap = await db.collection("jogos")
                .where("idGoleiro", "==", uid)
                .where("status", "in", ["fechado", "finalizado"])
                .where("dataHora", ">=", admin.firestore.Timestamp.fromDate(inicioDoDia))
                .where("dataHora", "<=", admin.firestore.Timestamp.fromDate(fimDoDia))
                .get();

            for (const doc of conflitosSnap.docs) {
                if (doc.id === idJogo) continue;
                const ex = doc.data();
                const inicioEx = ex.dataHora.toDate();
                const duracaoEx = ex.duracao || 60;
                let fimEx = new Date(inicioEx.getTime() + duracaoEx * 60000);
                const localEx = (ex.local || "").toString().trim().toLowerCase();
                const precisaDeslocamento = localEx !== localNovo;
                if (precisaDeslocamento) {
                    fimEx = new Date(fimEx.getTime() + 30 * 60000);
                }
                if (inicioNovo < fimEx && fimNovo > inicioEx) {
                    throw new HttpsError(
                        "failed-precondition",
                        precisaDeslocamento
                            ? `CONFLITO: Você já tem jogo em outro local. Precisa de 30min para deslocamento.`
                            : `CONFLITO: Você já tem um jogo neste horário.`
                    );
                }
            }
        }

        // Transaction atómica — só um goleiro vence
        await db.runTransaction(async (transaction) => {
            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) {
                throw new HttpsError("not-found", "Jogo não encontrado.");
            }
            const jogo = jogoSnap.data();
            if ((jogo.status || "") !== "aberto") {
                throw new HttpsError(
                    "failed-precondition",
                    "Ops! Outro goleiro foi mais rápido e já aceitou essa partida."
                );
            }
            if (jogo.idGoleiro) {
                throw new HttpsError(
                    "failed-precondition",
                    "Ops! Outro goleiro foi mais rápido e já aceitou essa partida."
                );
            }

            transaction.update(jogoRef, {
                status: "fechado",
                idGoleiro: uid,
                nomeGoleiro: nomeGoleiro,
                aceitoEm: admin.firestore.FieldValue.serverTimestamp(),
                editadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Notifica contratante
            if (jogo.idContratante) {
                const pushRef = db.collection("notificacoes").doc();
                let diaMes = "";
                let horaStr = "";
                if (jogo.dataHora) {
                    const d = jogo.dataHora.toDate();
                    diaMes = `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}`;
                    horaStr = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
                }
                const local = (jogo.local || "").toString().split("(")[0].trim();
                transaction.set(pushRef, {
                    idUsuario: jogo.idContratante,
                    titulo: "Goleiro Confirmado! 🧤",
                    mensagem: `O(a) ${nomeGoleiro} aceitou a convocação em ${local}${diaMes ? ` dia ${diaMes}` : ""}${horaStr ? ` às ${horaStr}` : ""}.`,
                    tipo: "aceitou_jogo",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });

        console.log(`[ACEITAR] jogo=${idJogo} goleiro=${uid}`);
        return { sucesso: true, idJogo, idGoleiro: uid };
    } catch (error) {
        console.error("[ACEITAR] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao aceitar convocação.");
    }
});


// ============================================================================
// 22. ⚖️ RESOLVER CONTESTAÇÃO (ADMIN) — Callable server-authoritative
// ============================================================================
// Vereditos:
//   favor_contratante → status contestado_aceito + estorno integral ao contratante (centavos + ledger)
//   favor_goleiro     → status finalizado + repasse ao goleiro (centavos + ledger recebimento_{idJogo})
// Regras de ouro: zero matemática no cliente, idempotencyKey, carteiras + ledger.
// ============================================================================
exports.resolverContestacaoAdmin = onCall(CALLABLE_OPTS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "O utilizador tem de estar logado.");

    const idJogo = request.data?.idJogo;
    const veredito = (request.data?.veredito || "").toString().toLowerCase();
    const idempotencyKey = request.data?.idempotencyKey;
    const motivoAdmin = (request.data?.motivoAdmin || "").toString().slice(0, 500);

    if (!idJogo || typeof idJogo !== "string") {
        throw new HttpsError("invalid-argument", "idJogo inválido.");
    }
    if (!["favor_contratante", "favor_goleiro"].includes(veredito)) {
        throw new HttpsError("invalid-argument", 'veredito deve ser "favor_contratante" ou "favor_goleiro".');
    }
    if (!idempotencyKey || typeof idempotencyKey !== "string" || idempotencyKey.length < 8) {
        throw new HttpsError("invalid-argument", "idempotencyKey obrigatória (UUID v4).");
    }

    const db = admin.firestore();

    // Pedágio de admin
    const adminSnap = await db.collection("usuarios").doc(uid).get();
    if (!adminSnap.exists || adminSnap.data().isAdmin !== true) {
        throw new HttpsError("permission-denied", "Acesso restrito a administradores.");
    }

    const jogoRef = db.collection("jogos").doc(idJogo);
    const ledgerRef = db.collection("ledger").doc(idempotencyKey);

    try {
        return await db.runTransaction(async (transaction) => {
            const ledgerSnap = await transaction.get(ledgerRef);
            if (ledgerSnap.exists) {
                return {
                    sucesso: true,
                    mensagem: "Veredito já processado.",
                    jaProcessado: true,
                    veredito: ledgerSnap.data().veredito || veredito,
                };
            }

            const jogoSnap = await transaction.get(jogoRef);
            if (!jogoSnap.exists) throw new HttpsError("not-found", "Jogo não encontrado.");

            const jogo = jogoSnap.data();
            const statusAtual = (jogo.status || "").toString();

            if (statusAtual !== "contestado") {
                throw new HttpsError(
                    "failed-precondition",
                    `Jogo não está em contestação (status: ${statusAtual}).`
                );
            }

            const idContratante = jogo.idContratante || null;
            const idGoleiro = jogo.idGoleiro || null;

            // --- Valor bruto pago pelo contratante (centavos) ---
            let valorBrutoCentavos = 0;
            if (typeof jogo.pagoEmCentavos === "number" && jogo.pagoEmCentavos > 0) {
                valorBrutoCentavos = Math.round(jogo.pagoEmCentavos);
            } else if (typeof jogo.valor === "number") {
                valorBrutoCentavos = Math.round(jogo.valor * 100);
            }

            // --- Repasse líquido do goleiro (centavos) ---
            let valorRepasseCentavos = 0;
            if (typeof jogo.valorGoleiroCentavos === "number" && jogo.valorGoleiroCentavos >= 0) {
                valorRepasseCentavos = Math.round(jogo.valorGoleiroCentavos);
            } else if (typeof jogo.valorGoleiro === "number" && jogo.valorGoleiro >= 0) {
                valorRepasseCentavos = Math.round(jogo.valorGoleiro * 100);
            } else if (typeof jogo.pagoEmCentavos === "number" && typeof jogo.taxaAplicadaCentavos === "number") {
                valorRepasseCentavos = Math.max(0, Math.round(jogo.pagoEmCentavos) - Math.round(jogo.taxaAplicadaCentavos));
            } else if (typeof jogo.pagoEmCentavos === "number" && typeof jogo.taxaAplicada === "number") {
                valorRepasseCentavos = Math.max(0, Math.round(jogo.pagoEmCentavos) - Math.round(jogo.taxaAplicada * 100));
            } else if (typeof jogo.valor === "number" && typeof jogo.taxaAplicada === "number") {
                valorRepasseCentavos = Math.max(0, Math.round((jogo.valor - jogo.taxaAplicada) * 100));
            } else {
                valorRepasseCentavos = valorBrutoCentavos;
            }

            // ============================================================
            // VEREDITO: FAVOR CONTRATANTE → estorno integral + contestado_aceito
            // ============================================================
            if (veredito === "favor_contratante") {
                if (!validarTransicao("contestado", "contestado_aceito")) {
                    throw new HttpsError("failed-precondition", "Transição contestado→contestado_aceito inválida.");
                }
                if (!idContratante) {
                    throw new HttpsError("failed-precondition", "Jogo sem contratante.");
                }

                let novoSaldo = 0;
                if (valorBrutoCentavos > 0) {
                    const carteiraRef = db.collection("carteiras").doc(idContratante);
                    const cSnap = await transaction.get(carteiraRef);
                    const saldoAtual = cSnap.exists ? (cSnap.data().saldoCentavos || 0) : 0;
                    novoSaldo = saldoAtual + valorBrutoCentavos;

                    transaction.set(carteiraRef, {
                        saldoCentavos: novoSaldo,
                        atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                    }, { merge: true });
                }

                transaction.update(jogoRef, {
                    status: "contestado_aceito",
                    "contestacao.statusMediacao": "resolvido_admin_favor_contratante",
                    "contestacao.finalizadoEm": admin.firestore.FieldValue.serverTimestamp(),
                    "contestacao.julgadoPor": uid,
                    "contestacao.motivoAdmin": motivoAdmin || "Veredito admin: favor do contratante",
                    dataJulgamento: admin.firestore.FieldValue.serverTimestamp(),
                    julgadoPor: uid,
                    valorEstornadoCentavos: valorBrutoCentavos,
                });

                // Estatísticas (não financeiras)
                if (idGoleiro) {
                    transaction.set(db.collection("usuarios").doc(idGoleiro), {
                        jogosContestados: admin.firestore.FieldValue.increment(-1),
                        faltas: admin.firestore.FieldValue.increment(1),
                    }, { merge: true });
                }
                if (idContratante) {
                    transaction.set(db.collection("usuarios").doc(idContratante), {
                        jogosContestados: admin.firestore.FieldValue.increment(-1),
                    }, { merge: true });
                }

                transaction.set(ledgerRef, {
                    tipo: "estorno_contestacao_admin",
                    uid: idContratante,
                    idJogo: idJogo,
                    idGoleiro: idGoleiro,
                    valorCentavos: valorBrutoCentavos,
                    saldoAposCentavos: novoSaldo,
                    idempotencyKey: idempotencyKey,
                    veredito: "favor_contratante",
                    descricao: "Veredito Admin: estorno ao contratante",
                    origem: "resolverContestacaoAdmin",
                    julgadoPor: uid,
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });

                // Notificações
                if (idContratante) {
                    const pushRef = db.collection("notificacoes").doc();
                    transaction.set(pushRef, {
                        idUsuario: idContratante,
                        titulo: "Disputa resolvida a seu favor ✅",
                        mensagem: `R$ ${(valorBrutoCentavos / 100).toFixed(2).replace(".", ",")} voltaram à sua carteira.`,
                        tipo: "contestacao_admin_contratante",
                        idJogo: idJogo,
                        lida: false,
                        data: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }
                if (idGoleiro) {
                    const pushRef = db.collection("notificacoes").doc();
                    transaction.set(pushRef, {
                        idUsuario: idGoleiro,
                        titulo: "Disputa resolvida",
                        mensagem: "O suporte analisou a contestação e o valor foi devolvido ao contratante.",
                        tipo: "contestacao_admin_goleiro",
                        idJogo: idJogo,
                        lida: false,
                        data: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }

                console.log(`[ADMIN_CONTESTACAO] favor_contratante jogo=${idJogo} estorno=${valorBrutoCentavos}`);
                return {
                    sucesso: true,
                    veredito: "favor_contratante",
                    statusFinal: "contestado_aceito",
                    valorCentavos: valorBrutoCentavos,
                    jaProcessado: false,
                };
            }

            // ============================================================
            // VEREDITO: FAVOR GOLEIRO → finalizado + pagamento (ledger estável)
            // ============================================================
            if (!validarTransicao("contestado", "finalizado")) {
                throw new HttpsError("failed-precondition", "Transição contestado→finalizado inválida.");
            }
            if (!idGoleiro) {
                throw new HttpsError("failed-precondition", "Jogo sem goleiro.");
            }

            // Ledger estável de recebimento (mesma chave do robô / finalizarJogo)
            const ledgerRecebimentoRef = db.collection("ledger").doc(`recebimento_${idJogo}`);
            const ledgerRecebSnap = await transaction.get(ledgerRecebimentoRef);
            if (ledgerRecebSnap.exists) {
                // Já pago por outro fluxo — só fecha a mediação
                transaction.update(jogoRef, {
                    status: "finalizado",
                    "contestacao.statusMediacao": "resolvido_admin_favor_goleiro",
                    "contestacao.finalizadoEm": admin.firestore.FieldValue.serverTimestamp(),
                    "contestacao.julgadoPor": uid,
                    "contestacao.motivoAdmin": motivoAdmin || "Veredito admin: favor do goleiro (já pago)",
                    dataJulgamento: admin.firestore.FieldValue.serverTimestamp(),
                    julgadoPor: uid,
                });
                transaction.set(ledgerRef, {
                    tipo: "veredito_admin_ja_pago",
                    uid: idGoleiro,
                    idJogo: idJogo,
                    valorCentavos: 0,
                    idempotencyKey: idempotencyKey,
                    veredito: "favor_goleiro",
                    descricao: "Veredito Admin favor goleiro — recebimento já existia",
                    origem: "resolverContestacaoAdmin",
                    julgadoPor: uid,
                    criadoEm: admin.firestore.FieldValue.serverTimestamp(),
                });
                return {
                    sucesso: true,
                    veredito: "favor_goleiro",
                    statusFinal: "finalizado",
                    valorCentavos: ledgerRecebSnap.data().valorCentavos || 0,
                    jaProcessado: true,
                    mensagem: "Pagamento já havia sido processado.",
                };
            }

            let novoSaldoGoleiro = 0;
            if (valorRepasseCentavos > 0) {
                const carteiraRef = db.collection("carteiras").doc(idGoleiro);
                const cSnap = await transaction.get(carteiraRef);
                const saldoAtual = cSnap.exists ? (cSnap.data().saldoCentavos || 0) : 0;
                novoSaldoGoleiro = saldoAtual + valorRepasseCentavos;

                transaction.set(carteiraRef, {
                    saldoCentavos: novoSaldoGoleiro,
                    atualizadoEm: admin.firestore.FieldValue.serverTimestamp(),
                }, { merge: true });
            }

            transaction.set(ledgerRecebimentoRef, {
                tipo: "recebimento_jogo",
                uid: idGoleiro,
                idJogo: idJogo,
                valorCentavos: valorRepasseCentavos,
                saldoAposCentavos: novoSaldoGoleiro,
                idempotencyKey: `recebimento_${idJogo}`,
                descricao: `Recebimento (veredito admin): ${jogo.local || "Pelada"}`,
                origem: "resolverContestacaoAdmin",
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.set(ledgerRef, {
                tipo: "veredito_admin_favor_goleiro",
                uid: idGoleiro,
                idJogo: idJogo,
                valorCentavos: valorRepasseCentavos,
                saldoAposCentavos: novoSaldoGoleiro,
                idempotencyKey: idempotencyKey,
                veredito: "favor_goleiro",
                descricao: "Veredito Admin: pagamento ao goleiro",
                origem: "resolverContestacaoAdmin",
                julgadoPor: uid,
                criadoEm: admin.firestore.FieldValue.serverTimestamp(),
            });

            transaction.update(jogoRef, {
                status: "finalizado",
                "contestacao.statusMediacao": "resolvido_admin_favor_goleiro",
                "contestacao.finalizadoEm": admin.firestore.FieldValue.serverTimestamp(),
                "contestacao.julgadoPor": uid,
                "contestacao.motivoAdmin": motivoAdmin || "Veredito admin: favor do goleiro",
                dataJulgamento: admin.firestore.FieldValue.serverTimestamp(),
                julgadoPor: uid,
                pagoEm: admin.firestore.FieldValue.serverTimestamp(),
                finalizadoPorAdmin: true,
                valorPagoAoGoleiroCentavos: valorRepasseCentavos,
                valorPagoAoGoleiro: valorRepasseCentavos / 100,
            });

            // Estatísticas
            transaction.set(db.collection("usuarios").doc(idGoleiro), {
                jogosContestados: admin.firestore.FieldValue.increment(-1),
                atuadas: admin.firestore.FieldValue.increment(1),
            }, { merge: true });
            if (idContratante) {
                transaction.set(db.collection("usuarios").doc(idContratante), {
                    jogosContestados: admin.firestore.FieldValue.increment(-1),
                }, { merge: true });
            }

            // Notificações
            if (idGoleiro) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: idGoleiro,
                    titulo: "Disputa resolvida a seu favor 💰",
                    mensagem: `R$ ${(valorRepasseCentavos / 100).toFixed(2).replace(".", ",")} foram creditados na sua carteira.`,
                    tipo: "contestacao_admin_goleiro",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
            if (idContratante) {
                const pushRef = db.collection("notificacoes").doc();
                transaction.set(pushRef, {
                    idUsuario: idContratante,
                    titulo: "Disputa resolvida",
                    mensagem: "O suporte analisou a contestação e o pagamento foi liberado ao goleiro.",
                    tipo: "contestacao_admin_contratante",
                    idJogo: idJogo,
                    lida: false,
                    data: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`[ADMIN_CONTESTACAO] favor_goleiro jogo=${idJogo} repasse=${valorRepasseCentavos}`);
            return {
                sucesso: true,
                veredito: "favor_goleiro",
                statusFinal: "finalizado",
                valorCentavos: valorRepasseCentavos,
                jaProcessado: false,
            };
        });
    } catch (error) {
        console.error("[ADMIN_CONTESTACAO] Erro:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", "Falha ao resolver contestação.");
    }
});
