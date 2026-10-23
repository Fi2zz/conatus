/// 记忆召回探针：在真实 nava 数据上量化「关键词召回漏掉多少语义相关条目」。
///
/// 扫描 `~/.nava/projects/*/memory.json` 与同目录 `sessions/*.jsonl`：对每条用户
/// 消息用**真实的** [MemoryStore] 召回，再用字符 bigram 余弦近似「语义相关」，
/// 统计触发率 / MISS 率（embedding 能救回的部分）/ 弱命中 / 注入成本。
///
/// 用法：`dart run tool/memory_probe.dart`
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'memory_probe_math.dart';

class _Turn {
  _Turn(this.time, this.text);
  final String time;
  final String text;
}

class _Project {
  _Project(this.name, this.memory, this.turns);
  final String name;
  final MemoryStore memory;
  final List<_Turn> turns;
  int get entries => memory.length;
}

Future<void> main() async {
  final String home = Platform.environment['HOME'] ?? '';
  final Directory root = Directory('$home/.nava/projects');
  if (!root.existsSync()) {
    stderr.writeln('未找到 $root');
    exitCode = 1;
    return;
  }
  final List<_Project> projects = <_Project>[];
  for (final Directory dir in root.listSync().whereType<Directory>()) {
    final _Project project = await _load(dir);
    if (project.entries > 0 || project.turns.isNotEmpty) projects.add(project);
  }
  final _Stats stats = _Stats();
  stdout.writeln('== corpus ==');
  for (final _Project project in projects) {
    stdout.writeln(
      '  ${project.turns.length.toString().padLeft(3)} turns  '
      '${project.entries.toString().padLeft(3)} entries  ${project.name}',
    );
    stats.addProject(project);
  }
  stats.report();
}

Future<_Project> _load(Directory dir) async {
  final MemoryStore memory = MemoryStore();
  final File memoryFile = File('${dir.path}/memory.json');
  if (memoryFile.existsSync()) {
    final Object? decoded = jsonDecode(await memoryFile.readAsString());
    for (final Object? item in decoded is List ? decoded : const <Object?>[]) {
      if (item is! Map) continue;
      final MemoryEntry entry = MemoryEntry.fromJson(
        Map<String, Object?>.from(item),
      );
      if (entry.text.isNotEmpty) {
        await memory.remember(entry.text, tags: entry.tags);
      }
    }
  }
  final List<_Turn> turns = <_Turn>[];
  for (final File file in _sessionFiles(dir)) {
    for (final String line in await file.readAsLines()) {
      final _Turn? turn = _turnOf(line);
      if (turn != null) turns.add(turn);
    }
  }
  turns.sort((_Turn a, _Turn b) => a.time.compareTo(b.time));
  return _Project(dir.path.split(Platform.pathSeparator).last, memory, turns);
}

Iterable<File> _sessionFiles(Directory dir) {
  final Directory sessions = Directory('${dir.path}/sessions');
  if (!sessions.existsSync()) return const <File>[];
  return sessions.listSync().whereType<File>().where(
    (File f) => f.path.endsWith('.jsonl'),
  );
}

_Turn? _turnOf(String line) {
  if (line.trim().isEmpty) return null;
  final Object? decoded = jsonDecode(line);
  if (decoded is! Map || decoded['type'] != 'user/message') return null;
  final Object? data = decoded['data'];
  if (data is! Map) return null;
  final Object? text = data['text'];
  if (text is! String || text.trim().isEmpty) return null;
  return _Turn('${decoded['time'] ?? ''}', text.trim());
}

class _Stats {
  int queries = 0;
  int fired = 0;
  int misses = 0;
  int weak = 0;
  int injected = 0;
  int injectedChars = 0;
  final List<String> rows = <String>[];

  void addProject(_Project project) {
    for (final _Turn turn in project.turns) {
      final List<MemoryEntry> hits = project.memory.recall(turn.text);
      final double bestCos = project.memory.entries
          .map((MemoryEntry e) => cosineOf(turn.text, e.text))
          .fold(0.0, math.max);
      final bool hit = hits.isNotEmpty;
      final bool miss = !hit && bestCos >= relevantCos;
      final bool weakHit = hit && bestCos < 0.15;
      queries++;
      if (hit) fired++;
      if (miss) misses++;
      if (weakHit) weak++;
      injected += hits.length;
      injectedChars += hits.fold(
        0,
        (int n, MemoryEntry e) => n + e.text.length,
      );
      rows.add(
        '  ${miss ? 'MISS' : (weakHit ? 'weak' : 'ok  ')} '
        'cos=${bestCos.toStringAsFixed(2)} hits=${hits.length} '
        '| ${_clip(turn.text)}',
      );
    }
  }

  void report() {
    if (queries == 0) {
      stdout.writeln('\n没有可评估的查询（记忆或会话为空）');
      return;
    }
    stdout.writeln('\n== results ==');
    stdout.writeln('  queries            : $queries');
    stdout.writeln(
      '  keyword fired      : $fired '
      '(${(fired / queries * 100).toStringAsFixed(0)}%)',
    );
    stdout.writeln(
      '  recall MISS        : $misses '
      '(${(misses / queries * 100).toStringAsFixed(0)}%)',
    );
    stdout.writeln('  weak/spurious hit  : $weak');
    stdout.writeln(
      '  mean injected      : '
      '${(injected / queries).toStringAsFixed(1)} 条 / '
      '${(injectedChars / queries).toStringAsFixed(0)} 字符',
    );
    stdout.writeln(
      '  miss 95% upper     : '
      '${(wilsonUpper(misses, queries) * 100).toStringAsFixed(0)}%',
    );
    stdout.writeln('\n== per query ==');
    for (final String row in rows) {
      stdout.writeln(row);
    }
  }
}

String _clip(String text) {
  final String flat = text.replaceAll('\n', ' ');
  return flat.length <= 34 ? flat : '${flat.substring(0, 34)}…';
}
