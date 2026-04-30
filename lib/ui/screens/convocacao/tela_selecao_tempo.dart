import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

// Modelo de dados para retorno
class DadosTempo {
  final DateTime data;
  final TimeOfDay hora;
  final int duracao; // Agora sempre em MINUTOS

  DadosTempo({required this.data, required this.hora, required this.duracao});
}

class TelaSelecaoTempo extends StatefulWidget {
  final DateTime? dataInicial;
  final TimeOfDay? horaInicial;

  const TelaSelecaoTempo({super.key, this.dataInicial, this.horaInicial});

  @override
  State<TelaSelecaoTempo> createState() => _TelaSelecaoTempoState();
}

class _TelaSelecaoTempoState extends State<TelaSelecaoTempo> {
  DateTime? dataSelt;
  TimeOfDay horaSelt = const TimeOfDay(hour: 18, minute: 0);
  int duracaoSeltHoras = 1; // Controle interno da UI em horas
  final Color primaryColor = const Color(0xFF00E676);

  late FixedExtentScrollController _scrollController;

  double get focoEstilo => dataSelt == null ? 0.3 : 1.0;

  @override
  void initState() {
    super.initState();
    
    // 1. Carrega os dados iniciais
    dataSelt = widget.dataInicial;
    if (widget.horaInicial != null) {
      horaSelt = widget.horaInicial!;
    }

    // 2. Calcula o index para o Picker (intervalos de 15 min)
    int initialIndex = (horaSelt.hour * 4) + (horaSelt.minute ~/ 15);
    _scrollController = FixedExtentScrollController(initialItem: initialIndex);

    // 3. Abre o calendário automaticamente se for um novo cadastro
    if (widget.dataInicial == null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _abrirCalendario();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _abrirCalendario() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dataSelt ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: primaryColor),
        ), 
        child: child!,
      ),
    );

    if (d != null) {
      setState(() => dataSelt = d);
    }
  }

  List<String> _gerarHorarios() {
    return List.generate(96, (i) {
      final h = (i ~/ 4).toString().padLeft(2, '0');
      final m = ((i % 4) * 15).toString().padLeft(2, '0');
      return "$h:$m";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Data, Início e Duração", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SELEÇÃO DE DATA
          ListTile(
            title: const Text("Data:", style: TextStyle(color: Colors.white70)),
            trailing: Text(
              dataSelt == null ? "Selecionar" : "${dataSelt!.day}/${dataSelt!.month}/${dataSelt!.year}",
              style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            onTap: _abrirCalendario,
          ),
          const Divider(color: Colors.white10),

          // SELEÇÃO DE HORA (PICKER)
          Expanded(
            child: Opacity(
              opacity: focoEstilo,
              child: AbsorbPointer(
                absorbing: dataSelt == null,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text("Horário de início:", style: TextStyle(color: Colors.white70)),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: _scrollController,
                        itemExtent: 55,
                        onSelectedItemChanged: (index) {
                          HapticFeedback.selectionClick();
                          final h = index ~/ 4;
                          final m = (index % 4) * 15;
                          setState(() {
                            horaSelt = TimeOfDay(hour: h, minute: m);
                          });
                        },
                        children: _gerarHorarios().map((h) => Center(
                          child: Text(h, style: const TextStyle(color: Colors.white, fontSize: 26))
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // SELEÇÃO DE DURAÇÃO
          Opacity(
            opacity: focoEstilo,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[900]!.withOpacity(0.5)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Duração da partida:", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      _botaoDuracao(1), // Representa 1 hora
                      const SizedBox(width: 15),
                      _botaoDuracao(2), // Representa 2 horas
                    ],
                  ),
                ],
              ),
            ),
          ),

          // BOTÃO CONFIRMAR
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: dataSelt != null ? primaryColor : Colors.grey[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: dataSelt == null ? null : () {
                  final agora = DateTime.now();
                  
                  // Validação: Não permitir horários que já passaram hoje
                  if (dataSelt!.year == agora.year &&
                      dataSelt!.month == agora.month &&
                      dataSelt!.day == agora.day) {
                    
                    final minutoSelt = (horaSelt.hour * 60) + horaSelt.minute;
                    final minutoAgora = (agora.hour * 60) + agora.minute;

                    if (minutoSelt < minutoAgora) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("O horário escolhido já passou!")),
                      );
                      return;
                    }
                  }

                  // RETORNO: Aqui acontece a mágica dos MINUTOS
                  Navigator.pop(context, DadosTempo(
                    data: dataSelt!, 
                    hora: horaSelt, 
                    duracao: duracaoSeltHoras * 60, // Salva 60 ou 120 no Firestore
                  ));
                },
                child: Text("CONFIRMAR", 
                    style: TextStyle(
                      color: dataSelt != null ? Colors.black : Colors.white24, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 16
                    )),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _botaoDuracao(int horas) {
    bool ativo = duracaoSeltHoras == horas;
    return Expanded(
      child: InkWell(
        onTap: dataSelt == null ? null : () => setState(() => duracaoSeltHoras = horas),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: ativo ? primaryColor : Colors.black,
            border: Border.all(color: ativo ? primaryColor : Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text("${horas}h 00min", 
                style: TextStyle(
                  color: ativo ? Colors.black : Colors.white, 
                  fontWeight: FontWeight.bold
                )),
          ),
        ),
      ),
    );
  }
}