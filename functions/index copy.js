// Usando a V2 para maior performance e concorrência
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { beforeUserCreated } = require("firebase-functions/v2/identity");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

// Configuração Global V2 (Obriga a rodar na América do Sul para reduzir latência)
setGlobalOptions({ region: "southamerica-east1" });

// ============================================================================
// 0. MÁQUINA DE ESTADOS (A Fonte da Verdade)
// ============================================================================
const ESTADOS_PERMITIDOS = {
    "aberto": ["fechado", "cancelado", "expirado"],
    "fechado": ["aberto", "cancelado", "finalizado", "contestado"],
    "contestado": ["contestado_aceito", "finalizado", "cancelado"],
    // Estados Finais:
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
// 1. FUNDAÇÃO: CRIAR PERFIL E CARTEIRA (Ao Autenticar)
// ============================================================================
// Esta função roda antes do utilizador existir na base de dados para garantir
// que a carteira já lá está quando ele abrir a app.
exports.criarPerfilECarteira = beforeUserCreated(async (event) => {
    const user = event.data;
    const db = admin.firestore();

    try {
        const batch = db.batch();
        const userRef = db.collection('usuarios').doc(user.uid);
        const carteiraRef = db.collection('carteiras').doc(user.uid);

        // 1. Cria a Carteira Financeira Intocável (Em Centavos)
        batch.set(carteiraRef, {
            saldoCentavos: 0,
            multasPendentesCentavos: 0,
            retidoCentavos: 0,
            atualizadoEm: admin.firestore.FieldValue.serverTimestamp()
        });

        // 2. Prepara o Perfil Base
        batch.set(userRef, {
            uid: user.uid,
            email: user.email ? user.email.toLowerCase() : null,
            nome: user.displayName || "Novo Usuário",
            fotoUrl: user.photoURL || "",
            // A categoria base vem do servidor
            categoria: "livre",
            ativo: true,
            criadoEm: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true }); // Merge caso a Etapa 1 do Flutter já tenha escrito algo

        await batch.commit();
        console.log(`[LEDGER] Carteira criada com sucesso para ${user.uid}`);

    } catch (error) {
        console.error(`[ERRO CRÍTICO] Falha ao criar carteira para ${user.uid}:`, error);
        // Não bloqueia a criação da conta, mas avisa nos logs
    }
});


// ============================================================================
// 2. NOTIFICAR NOVA PELADA (Convertido para V2)
// ============================================================================
exports.notificarNovaPelada = onDocumentCreated("jogos/{jogoId}", async (event) => {
    const snap = event.data;
    if (!snap) return;
    
    const jogo = snap.data();
    const db = admin.firestore();

    if (jogo.status !== 'aberto' || event.params.jogoId.startsWith('cancelado_')) {
        return;
    }

    const agoraUtc = new Date();
    let horaBrasil = agoraUtc.getUTCHours() - 3;
    if (horaBrasil < 0) horaBrasil += 24;

    if (horaBrasil < 8 || horaBrasil >= 22) return; 

    const jogoLat = jogo.latitude || jogo.lat;
    const jogoLng = jogo.longitude || jogo.lng;

    if (!jogoLat || !jogoLng) return;

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
            
            if (nivelGoleiro.includes('elite') || nivelGoleiro.includes('pared')) {
                rankGoleiro = 2;
            } else if (nivelGoleiro.includes('exp') || nivelGoleiro.includes('inter') || nivelGoleiro.includes('médio') || nivelGoleiro.includes('medio')) {
                rankGoleiro = 1;
            }

            if (rankGoleiro < rankExigido) continue; 

            const recebidasHojeSnap = await db.collection('notificacoes').where('idUsuario', '==', doc.id).where('data', '>=', inicioDoDia).get();
            if (recebidasHojeSnap.docs.filter(d => d.data().tipo === 'nova_pelada').length >= 2) continue; 

            const dHora = jogo.dataHora ? jogo.dataHora.toDate() : new Date();
            const diaMes = jogo.dataExibicao || `\({String(dHora.getDate()).padStart(2, '0')}/\){String(dHora.getMonth() + 1).padStart(2, '0')}`;
            const horaStr = jogo.horaExibicao || `\({String(dHora.getHours()).padStart(2, '0')}:\){String(dHora.getMinutes()).padStart(2, '0')}`;

            const novaNotificacaoRef = db.collection('notificacoes').doc();
            batch.set(novaNotificacaoRef, {
                idUsuario: doc.id,
                titulo: "⚽ Nova Convocação na Área!",
                mensagem: `Pelada de R$ \({valorParaGoleiro.toFixed(2)} dia\){diaMes} às \({horaStr} a apenas\){distancia.toFixed(1)}km de você!`,
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
// 3. PUSH UNIVERSAL E ADMIN (Mantidos iguais, mas em V2)
// ============================================================================
exports.dispararPushUniversal = onDocumentCreated("notificacoes/{docId}", async (event) => {
    const snap = event.data;
    if (!snap) return;
    const notificacao = snap.data();
    const idUsuarioDestino = notificacao.idUsuario;

    // A trava do Admin: Se tem publicoAlvo, é disparo em massa, ignora aqui.
    if (!idUsuarioDestino || notificacao.publicoAlvo) return;

    try {
        const userDoc = await admin.firestore().collection("usuarios").doc(idUsuarioDestino).get();
        const token = userDoc.data()?.fcmToken;

        if (!token) return;

        const payload = {
            token: token,
            notification: {
                title: notificacao.titulo,
                body: notificacao.mensagem,
            },
            data: {
                tipo: notificacao.tipo || 'geral',
                click_action: 'FLUTTER_NOTIFICATION_CLICK'
            }
        };

        if (notificacao.idJogo) {
            payload.data.idJogo = String(notificacao.idJogo);
        }

        await admin.messaging().send(payload);
    } catch (error) {
        console.error(`Erro no Push Universal:`, error);
    }
});

exports.dispararNotificacaoAdmin = onDocumentCreated("notificacoes/{docId}", async (event) => {
    const snap = event.data;
    if (!snap) return;
    const dados = snap.data();
    const alvo = dados.publicoAlvo; 

    if (!alvo) return;

    try {
        let query = admin.firestore().collection("usuarios");
        if (alvo !== "todos") {
            query = query.where("tipoPerfil", "==", alvo);
        }

        const usuariosSnapshot = await query.get();
        const tokens = [];

        usuariosSnapshot.forEach((doc) => {
            const fcmToken = doc.data().fcmToken;
            if (fcmToken) tokens.push(fcmToken);
        });

        if (tokens.length === 0) {
            return snap.ref.update({ status: "sem_destinatarios" });
        }

        const payload = {
            notification: { title: dados.titulo, body: dados.mensagem },
            tokens: tokens,
        };

        const response = await admin.messaging().sendMulticast(payload);
        
        return snap.ref.update({ 
            status: "concluido",
            sucessos: response.successCount,
            falhas: response.failureCount,
            dataProcessamento: admin.firestore.FieldValue.serverTimestamp()
        });

    } catch (error) {
        return snap.ref.update({ status: "erro_no_envio", erro: error.message });
    }
});

// ============================================================================
// 4. ROBÔ DE EXPIRAÇÃO DE JOGOS ABERTOS (Item 2.2 do Mapa)
// ============================================================================
exports.expirarJogosAbertos = onSchedule("every 15 minutes", async (event) => {
    const db = admin.firestore();
    const agora = admin.firestore.Timestamp.now();
    
    // Procura jogos ABERTOS que já passaram da data
    const jogosVencidos = await db.collection('jogos')
        .where('status', '==', 'aberto')
        .where('dataHora', '<', agora)
        .get();

    if (jogosVencidos.empty) return;

    console.log(`[JOB] Encontrados ${jogosVencidos.size} jogos abertos e vencidos.`);

    const promessas = [];

    jogosVencidos.forEach((doc) => {
        const idJogo = doc.id;
        const jogoData = doc.data();

        // Verifica a transição na máquina de estados
        if (!validarTransicao('aberto', 'expirado')) return;

        const operacao = db.runTransaction(async (transaction) => {
            const jogoRef = db.collection('jogos').doc(idJogo);
            
            // 1. Muda o estado
            transaction.update(jogoRef, { 
                status: 'expirado',
                editadoEm: admin.firestore.FieldValue.serverTimestamp()
            });

            // O estorno do dinheiro para o Contratante será feito na Etapa 3 (Callable)
            // Por enquanto, o robô só fecha a pelada para ela sumir do mapa dos Goleiros.

            // 2. Avisa o contratante
            const pushRef = db.collection('notificacoes').doc();
            transaction.set(pushRef, {
                idUsuario: jogoData.idContratante,
                titulo: "Atenção: Jogo Expirado ⏰",
                mensagem: `O seu jogo em ${jogoData.local} não encontrou goleiros a tempo e foi cancelado.`,
                tipo: "jogo_expirado",
                data: admin.firestore.FieldValue.serverTimestamp()
            });
        });

        promessas.push(operacao);
    });

    await Promise.all(promessas);
});


// As rotinas de pagamento, nível e gari ficarão congeladas aqui temporariamente
// até construirmos as Callables da Etapa 3 que vão mexer com a nova coleção de "Centavos".