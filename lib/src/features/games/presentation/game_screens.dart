import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/ai/phi_service.dart';
import '../../../services/ai/rag_service.dart';

class TriviaScreen extends StatefulWidget {
  const TriviaScreen({super.key});

  @override
  State<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends State<TriviaScreen> {
  final _questions = List.of(_triviaQuestions)..shuffle();
  int _index = 0;
  int _score = 0;
  bool _answered = false;

  @override
  Widget build(BuildContext context) {
    final question = _questions[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('Trivia')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вопрос ${_index + 1}/${_questions.length}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(question.question, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            for (final option in question.options)
              Card(
                child: ListTile(
                  title: Text(option),
                  tileColor: _answered
                      ? option == question.answer
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.1)
                      : null,
                  onTap: _answered
                      ? null
                      : () {
                          setState(() {
                            _answered = true;
                            if (option == question.answer) {
                              _score++;
                            }
                          });
                        },
                ),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Счет: $_score'),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _answered = false;
                      _index = (_index + 1) % _questions.length;
                    });
                  },
                  child: const Text('Далее'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GuessWordScreen extends StatefulWidget {
  const GuessWordScreen({super.key});

  @override
  State<GuessWordScreen> createState() => _GuessWordScreenState();
}

class _GuessWordScreenState extends State<GuessWordScreen> {
  late String _word;
  final _controller = TextEditingController();
  final _random = Random();
  String _feedback = '';

  @override
  void initState() {
    super.initState();
    _word = _guessWords[_random.nextInt(_guessWords.length)].toLowerCase();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Угадай слово')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Слово из ${_word.length} букв'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Введите слово'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _check,
              child: const Text('Проверить'),
            ),
            const SizedBox(height: 20),
            Text(_feedback),
          ],
        ),
      ),
    );
  }

  void _check() {
    final guess = _controller.text.trim().toLowerCase();
    if (guess == _word) {
      setState(() {
        _feedback = 'Верно! Слово: $_word';
        _word = _guessWords[_random.nextInt(_guessWords.length)].toLowerCase();
        _controller.clear();
      });
      return;
    }
    final matches = List.generate(_word.length, (index) => guess.length > index && guess[index] == _word[index]);
    setState(() {
      _feedback = 'Совпадений по позициям: ${matches.where((e) => e).length}';
    });
  }
}

class StoryWeaverScreen extends ConsumerStatefulWidget {
  const StoryWeaverScreen({super.key});

  @override
  ConsumerState<StoryWeaverScreen> createState() => _StoryWeaverScreenState();
}

class _StoryWeaverScreenState extends ConsumerState<StoryWeaverScreen> {
  final _controller = TextEditingController();
  String? _story;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cosmic Story Weaver')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Тема истории (по желанию)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _generate,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Создать историю'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _story == null
                  ? const Center(child: Text('История появится здесь.'))
                  : SingleChildScrollView(child: Text(_story!)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
    });
    final topic = _controller.text.trim();
    final contexts = <String>['Космос', 'Будущее', 'Путешествие через тессеракт'];
    final phi = ref.read(phiServiceProvider);
    await phi.ensureLoaded();
    final result = await phi.generate(
      'Создай атмосферную научно-фантастическую историю на русском языке. Тема: ${topic.isEmpty ? 'по выбору модели' : topic}.',
      contexts: contexts,
    );
    setState(() {
      _story = result ?? 'Не удалось сгенерировать историю оффлайн :(';
      _loading = false;
    });
  }
}

class TriviaQuestion {
  const TriviaQuestion({required this.question, required this.options, required this.answer});

  final String question;
  final List<String> options;
  final String answer;
}

const _triviaQuestions = <TriviaQuestion>[
  TriviaQuestion(
    question: 'Когда началась Великая Отечественная война?',
    options: ['1941', '1939', '1945', '1943'],
    answer: '1941',
  ),
  TriviaQuestion(
    question: 'Какая планета самая большая в Солнечной системе?',
    options: ['Сатурн', 'Юпитер', 'Нептун', 'Земля'],
    answer: 'Юпитер',
  ),
  TriviaQuestion(
    question: 'Сколько континентов на Земле?',
    options: ['5', '6', '7', '4'],
    answer: '6',
  ),
  TriviaQuestion(
    question: 'Кто сформулировал законы движения планет?',
    options: ['Коперник', 'Кеплер', 'Ньютон', 'Галилей'],
    answer: 'Кеплер',
  ),
];

const _guessWords = <String>['галактика', 'квант', 'звезда', 'пульсар', 'орбита', 'метеор'];
