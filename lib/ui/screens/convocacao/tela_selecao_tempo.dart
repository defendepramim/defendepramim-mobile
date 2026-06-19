import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class DadosTempo {
  final DateTime data;
  final TimeOfDay hora;
  final int duracao;

  DadosTempo({required this.data, required this.hora, required this.duracao});
}

class TelaSelecaoTempo extends StatefulWidget {
  final DateTime? dataInicial;
  final TimeOfDay? horaInicial;
  
  // 🟢 AQUI ESTÁ A CHAVE: A tela agora aceita a função que vem de fora!
  final Future<String?> Function(DateTime dataHoraDesejada, int duracaoMinutos)? validadorExterno;

  const TelaSelecaoTempo({super.key, this.dataInicial, this.horaInicial, this.validadorExterno});

  @override
  State<TelaSelecaoTempo> createState() => _TelaSelecaoTempoState();
}

class _TelaSelecaoTempoState extends State<TelaSelecaoTempo> {
  DateTime? dataSelt;
  TimeOfDay horaSelt = const TimeOfDay(hour: 18, minute: 0);
  int duracaoSeltHoras = 1; 
  final Color primaryColor = const Color(0xFF00E676);

  late FixedExtentScrollController _scrollController;
  
  String? _erroValidacao;
  bool _validando = false; 

  double get focoEstilo => dataSelt == null ? 0.3 : 1.0;

  @override
  void initState() {
    super.initState();
    
    dataSelt = widget.dataInicial;
    if (widget.horaInicial != null) {
      horaSelt = widget.horaInicial!;
    }

    int initialIndex = (horaSelt.hour * 4) + (horaSelt.minute ~/ 15);
    _scrollController = FixedExtentScrollController(initialItem: initialIndex);

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

  void _limparErro() {
    if (_erroValidacao != null) {
      setState(() => _erroValidacao = null);
    }
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
      _limparErro();
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
      body: SafeArea( 
        top: true,    
        bottom: true, 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: const Text("Data:", style: TextStyle(color: Colors.white70)),
              trailing: Text(
                dataSelt == null ? "Selecionar" : "${dataSelt!.day}/${dataSelt!.month}/${dataSelt!.year}",
                style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              onTap: _abrirCalendario,
            ),
            const Divider(color: Colors.white10),

            Expanded(
              child: Opacity(
                opacity: focoEstilo,
                child: AbsorbPointer(
                  absorbing: dataSelt == null || _validando,
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
                            _limparErro();
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
                        _botaoDuracao(1), 
                        const SizedBox(width: 15),
                        _botaoDuracao(2), 
                      ],
                    ),
                  ],
                ),
              ),
            ),

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
                  onPressed: (dataSelt == null || _validando) ? null : () async {
                    final dataHoraJogo = DateTime(
                      dataSelt!.year,
                      dataSelt!.month,
                      dataSelt!.day,
                      horaSelt.hour,
                      horaSelt.minute,
                    );

                    // Validação de tempo no passado
                    if (dataHoraJogo.isBefore(DateTime.now())) {
                      setState(() => _erroValidacao = "O horário escolhido já passou!");
                      return;
                    }

                    // 🟢 A MÁGICA ACONTECE AQUI: Chama o validador do Firebase que você passou!
                    if (widget.validadorExterno != null) {
                      setState(() {
                        _validando = true;
                        _erroValidacao = null;
                      });
                      
                      final erroAgenda = await widget.validadorExterno!(dataHoraJogo, duracaoSeltHoras * 60);
                      
                      if (!mounted) return;
                      
                      setState(() => _validando = false);
                      
                      if (erroAgenda != null) {
                        setState(() => _erroValidacao = erroAgenda);
                        return; 
                      }
                    }

                    Navigator.pop(context, DadosTempo(
                      data: dataSelt!, 
                      hora: horaSelt, 
                      duracao: duracaoSeltHoras * 60,
                    ));
                  },
                  child: _validando 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : Text("CONFIRMAR", 
                        style: TextStyle(
                          color: dataSelt != null ? Colors.black : Colors.white24, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 16
                        )),
                ),
              ),
            ),

            if (_erroValidacao != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                color: Colors.redAccent.shade200, 
                child: Text(
                  _erroValidacao!,
                  style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _botaoDuracao(int horas) {
    bool ativo = duracaoSeltHoras == horas;
    return Expanded(
      child: InkWell(
        onTap: (dataSelt == null || _validando) ? null : () {
          setState(() => duracaoSeltHoras = horas);
          _limparErro(); 
        },
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