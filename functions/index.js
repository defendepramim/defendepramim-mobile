const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.liberarPagamentosAutomaticos = functions.pubsub
    .schedule('every 60 minutes')
    .onRun(async (context) => {
        const db = admin.firestore();
        const agora = admin.firestore.Timestamp.now().toDate();
        const limite = new Date(agora.getTime() - (12 * 60 * 60 * 1000));

        const snapshot = await db.collection('jogos')
            .where('status', '==', 'fechado')
            .where('dataHoraFim', '<=', admin.firestore.Timestamp.fromDate(limite))
            .get();

        if (snapshot.empty) return null;

        const promessas = [];

        snapshot.forEach(doc => {
            const jogo = doc.data();
            const jogoRef = doc.ref;

            const transacao = db.runTransaction(async (t) => {
                const goleiroRef = db.collection('usuarios').doc(jogo.idGoleiro);
                
                t.update(jogoRef, { 
                    status: 'finalizado', 
                    finalizadoAutomaticamente: true,
                    notificadoNoApp: false,
                    pagoEm: admin.firestore.FieldValue.serverTimestamp() // Usando seu padrão 'pagoEm'
                });

                t.update(goleiroRef, { 
                    saldo: admin.firestore.FieldValue.increment(jogo.valor) 
                });
            });

            promessas.push(transacao);
        });

        await Promise.all(promessas);
        return null;
    });