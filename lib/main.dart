
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KL Line Tycoon',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: Colors.indigo,
    useMaterial3: true),
    home: const Game(),
  );
}

const names = ['KL Sentral', 'Pasar Seni', 'Masjid Jamek', 'Bukit Bintang', 'KLCC'];
const demand = [0.5, 0.35, 0.35, 0.4, 0.45];
const people = ['Pn. Aminah', 'En. Raju', 'Ah Meng', 'Cik Siti', 'Dr. Lim'];
const shopNames = ['🍛 Nasi Lemak stall', '🧋 Teh Tarik kiosk', '🏪 Mini market'];
const shopRate = [0.3, 0.2, 0.5];
const shopBase = [100.0, 80.0, 150.0];
const trainColors = [Colors.teal, Colors.deepOrange, Colors.purple, Colors.blue, Colors.pink];

String rm(double v) {
  final p = v.toStringAsFixed(2).split('.');
  final i = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return 'RM $i.${p[1]}';
}

String two(int n) => n.toString().padLeft(2, '0');

class Pax {
  final int from, dest;
  Pax(this.from, this.dest);
}

class Station {
  final List<Pax> q = [];
  int hall = 0, boarded = 0;
  List<int> shops = [0, 0, 0];
  double rating = 3, acc = 0;
  int get cap => 20 + hall * 10;
}

class Train {
  int cur = 0, next = 1, dir = 1, carried = 0;
  double pos = 0, dwell = 1.5;
  final List<Pax> load = [];
}

class Quest {
  final String type, title;
  final double reward;
  final int target;
  double time;
  int progress = 0, station = 0, train = 0;
  Pax? pax;
  Quest(this.type, this.title, this.reward, this.time, {this.target = 1});
}

class Game extends StatefulWidget {
  const Game({super.key});
  @override
  State<Game> createState() => _GameState();
}

class _GameState extends State<Game> {
  static const double dt = 0.05;
  final rng = Random();
  Timer? _timer;

  double money = 150, questT = 3, msgT = 0;
  String msg = '';
  int riders = 0, questsDone = 0, sel = 0;
  int capLv = 0, speedLv = 0, fareLv = 0, promoLv = 0;
  bool paused = false;
  double gameSpeed = 1.0;

  double get incomePerSecond {
    double total = 0;
    for (final s in stations) {
      for (int k = 0; k < 3; k++) {
        total += s.shops[k] * shopRate[k];
      }
    }
    return total;
  }
  final stations = List.generate(5, (_) => Station());
  final trains = [Train()];
  final quests = <Quest>[];

  DateTime get myt => DateTime.now().toUtc().add(const Duration(hours: 8));
  double get timeFactor {
    final h = myt.hour + myt.minute / 60;
    if ((h >= 7 && h < 9.5) || (h >= 17 && h < 20)) return 3;
    if (h >= 23 || h < 5) return 0.3;
    return 1;
  }

  int get trainCap => 15 + capLv * 5;
  double get speed => 0.25 + speedLv * 0.04;
  double get avgRating => stations.map((s) => s.rating).reduce((a, b) => a + b) / 5;
  double cost(double base, double g, int lv) => base * pow(g, lv).toDouble();

  @override
void initState() {
super.initState();
_timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
}

@override
void dispose() {
_timer?.cancel();
super.dispose();
}

void _tick() {
if (paused || !mounted) return;
setState(() {
final step = dt * gameSpeed;
final f = timeFactor;
for (int i = 0; i < 5; i++) {
final s = stations[i];
s.acc += demand[i] * f * (1 + promoLv * 0.2) * (0.5 + s.rating * 0.25) * step;
while (s.acc >= 1) {
s.acc -= 1;
if (s.q.length < s.cap) {
int d;
do {
d = rng.nextInt(5);
} while (d == i);
s.q.add(Pax(i, d));
} else {
s.rating = max(0, s.rating - 0.03);
}
}
final shopLv = s.shops.fold<int>(0, (a, b) => a + b);
final target = (1 - s.q.length / s.cap) * 4 + min(1, shopLv / 6);
s.rating = (s.rating + (target - s.rating) * 0.1 * step).clamp(0.0, 5.0).toDouble();
double inc = 0;
for (int k = 0; k < 3; k++) {
inc += s.shops[k] * shopRate[k];
}
money += inc * (1 + s.q.length / 15) * step;
}
for (final t in trains) {
_move(t, step);
}
_questTick(step);
if (msgT > 0) msgT = max(0, msgT - step);
});
}

void _move(Train t, double step) {
if (t.dwell > 0) {
t.dwell = max(0, t.dwell - step);
return;
}
t.pos += t.dir * speed * step;
if ((t.dir > 0 && t.pos >= t.next) || (t.dir < 0 && t.pos <= t.next)) {
t.pos = t.next.toDouble();
_arrive(t, t.next);
}
}

void _arrive(Train t, int s) {
t.cur = s;
t.load.removeWhere((p) {
if (p.dest != s) return false;
money += (p.dest - p.from).abs() * 1.5 * (1 + fareLv * 0.15) *
(0.8 + avgRating.clamp(0.0, 5.0).toDouble() * 0.1);
riders++;
t.carried++;
for (final q in quests) {
if (q.type == 'peak') q.progress++;
if (q.pax == p) q.progress = q.target;
}
return true;
});
if (s == 0) t.dir = 1;
if (s == 4) t.dir = -1;
stations[s].q.removeWhere((p) {
if (t.load.length >= trainCap) return false;
if ((p.dest - s).sign != t.dir) return false;
t.load.add(p);
stations[s].boarded++;
return true;
});
t.next = s + t.dir;
t.dwell = 2.5;
}

void _tapTrain(int i) {
setState(() {
final t = trains[i];
for (final q in quests) {
if (q.type == 'evader' && q.train == i) q.progress = 1;
}
if (t.dwell > 0) {
t.dwell = 0;
money += 1;
for (final q in quests) {
if (q.type == 'rush') q.progress++;
}
}
});
}

void _questTick(double step) {
for (final q in quests.toList()) {
if (q.progress >= q.target) {
money += q.reward;
questsDone++;
msg = '✅ Quest done! +${rm(q.reward)}';
msgT = 4;
quests.remove(q);
} else {
q.time -= step;
if (q.time <= 0) {
if (q.type == 'lost') {
stations[q.station].rating = max(0, stations[q.station].rating - 0.5);
}
if (q.type == 'evader') money = max(0, money - 15);
msg = '❌ Quest failed: ${q.title}';
msgT = 4;
quests.remove(q);
}
}
}
questT -= step;
if (questT <= 0) {
questT = 18 + rng.nextInt(12).toDouble();
if (quests.length < 4) _newQuest();
}
}

void _newQuest() {
final ty = ['trip', 'rush', 'peak', 'lost', 'evader'][rng.nextInt(5)];
if (quests.any((q) => q.type == ty)) return;
switch (ty) {
case 'trip':
{
final a = rng.nextInt(5);
int b;
do {
b = rng.nextInt(5);
} while (b == a);
if (stations[a].q.length >= stations[a].cap) return;
final p = Pax(a, b);
stations[a].q.insert(0, p);
quests.add(Quest(ty, '${people[rng.nextInt(5)]}: ${names[a]} → ${names[b]}',
40 + 10.0 * (a - b).abs(), 100)
..pax = p);
break;
}
case 'rush':
quests.add(Quest(ty, 'Help trains depart: tap a stopped train 3 times', 25, 90, target: 3));
break;
case 'peak':
quests.add(Quest(ty, 'Rush hour: carry 25 passengers', 60, 90, target: 25));
break;
case 'lost':
quests.add(Quest(ty, 'Lost bag! Tap 🎒 on the map', 35, 45)
..station = rng.nextInt(5));
break;
case 'evader':
{
final ids = [for (int i = 0; i < trains.length; i++) if (trains[i].load.isNotEmpty) i];
if (ids.isEmpty) return;
quests.add(Quest(ty, 'Fare evader! Tap the 🕵️ train', 30, 25)
..train = ids[rng.nextInt(ids.length)]);
break;
}
}
}

void _spend(double c, VoidCallback f) {
if (money < c) return;
setState(() {
money -= c;
f();
});
}

void _showHelp() {
showDialog<void>(
context: context,
builder: (context) => AlertDialog(
title: const Text('How to play KL Line Tycoon'),
content: const SingleChildScrollView(
child: Text(
'BUILD YOUR NETWORK\n'
'• Select a station on the map to manage it.\n'
'• Upgrade waiting halls to increase passenger capacity.\n'
'• Build shops to earn passive income.\n\n'
'MANAGE YOUR TRAINS\n'
'• Buy trains to carry more passengers.\n'
'• Upgrade capacity and speed as demand grows.\n'
'• Tap a train while it is stopped to send it off early.\n\n'
'GROW YOUR RAILWAY\n'
'• Complete quests for bonus cash.\n'
'• Keep station ratings high by managing queues.\n'
'• Rush hour brings more passengers, but crowded stations lose reputation.',
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Got it'),
),
],
),
);
}

void _resetGame() {
setState(() {
money = 150;
questT = 3;
msgT = 0;
msg = 'Welcome back, Railway Manager!';
riders = 0;
questsDone = 0;
sel = 0;
capLv = 0;
speedLv = 0;
fareLv = 0;
promoLv = 0;
paused = false;
gameSpeed = 1;
for (int i = 0; i < stations.length; i++) {
stations[i] = Station();
}
trains
..clear()
..add(Train());
quests.clear();
});
}

Future<void> _confirmReset() async {
final confirmed = await showDialog<bool>(
context: context,
builder: (context) => AlertDialog(
title: const Text('Start a new game?'),
content: const Text('Your current railway progress will be lost.'),
actions: [
TextButton(
onPressed: () => Navigator.pop(context, false),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () => Navigator.pop(context, true),
child: const Text('New game'),
),
],
),
);
if (confirmed == true && mounted) _resetGame();
}

// ---------------- UI ----------------

@override
Widget build(BuildContext context) {
return DefaultTabController(
length: 3,
child: Scaffold(
backgroundColor: const Color(0xFF12141C),
body: SafeArea(
child: Column(children: [
_hud(),
_controls(),
_map(),
Expanded(
child: Container(
color: const Color(0xFF1C1F2B),
child: Column(children: [
const TabBar(tabs: [
Tab(text: 'Station'),
Tab(text: 'Trains'),
Tab(text: 'Quests'),
]),
Expanded(
child: TabBarView(children: [_stationTab(), _trainTab(), _questTab()]),
),
]),
),
),
]),
),
),
);
}

Widget _hud() {
final peak = timeFactor >= 3;
return Container(
padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
decoration: const BoxDecoration(
gradient: LinearGradient(colors: [Color(0xFF283593), Color(0xFF1A237E)])),
child: Column(children: [
Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(rm(money),
style: const TextStyle(
fontSize: 26, fontWeight: FontWeight.w800, color: Colors.amber)),
Text('＋${rm(incomePerSecond)}/sec shop income',
style: const TextStyle(fontSize: 10, color: Colors.white70)),
],
),
Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
Text('🕒 ${two(myt.hour)}:${two(myt.minute)} MYT',
style: const TextStyle(fontWeight: FontWeight.bold)),
Text(peak ? '🔥 Peak hour ×3' : timeFactor < 1 ? '🌙 Quiet hours' : 'Normal hours',
style: TextStyle(fontSize: 11, color: peak ? Colors.orangeAccent : Colors.white60)),
]),
]),
const SizedBox(height: 4),
Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
Text('⭐ ${avgRating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13)),
Text('👥 $riders riders', style: const TextStyle(fontSize: 13)),
Text('📋 $questsDone quests', style: const TextStyle(fontSize: 13)),
]),
if (msgT > 0)
Padding(
padding: const EdgeInsets.only(top: 4),
child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.amberAccent)),
),
]),
);
}

Widget _controls() {
return Container(
color: const Color(0xFF202638),
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
child: Row(
children: [
IconButton.filledTonal(
tooltip: paused ? 'Resume' : 'Pause',
onPressed: () => setState(() => paused = !paused),
icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
visualDensity: VisualDensity.compact,
),
Text(paused ? 'Paused' : 'Running',
style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
const Spacer(),
const Text('Speed', style: TextStyle(fontSize: 12, color: Colors.white70)),
const SizedBox(width: 6),
SegmentedButton<double>(
segments: const [
ButtonSegment(value: 1.0, label: Text('1×')),
ButtonSegment(value: 2.0, label: Text('2×')),
],
selected: {gameSpeed},
onSelectionChanged: (value) =>
setState(() => gameSpeed = value.first),
showSelectedIcon: false,
style: const ButtonStyle(
visualDensity: VisualDensity.compact,
textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
),
),
const SizedBox(width: 4),
IconButton(
tooltip: 'How to play',
onPressed: _showHelp,
icon: const Icon(Icons.help_outline_rounded),
visualDensity: VisualDensity.compact,
),
IconButton(
tooltip: 'New game',
onPressed: _confirmReset,
icon: const Icon(Icons.restart_alt_rounded),
visualDensity: VisualDensity.compact,
),
],
),
);
}

Widget _map() {
return SizedBox(
height: 190,
child: LayoutBuilder(builder: (c, box) {
final w = box.maxWidth;
double sx(double p) => 30 + p * (w - 60) / 4;
return Stack(children: [
Positioned(
left: 20,
right: 20,
top: 93,
child: Container(
height: 5,
decoration: BoxDecoration(
color: Colors.grey.shade600, borderRadius: BorderRadius.circular(3))),
),
for (int i = 0; i < 5; i++) ...[
Positioned(
left: sx(i.toDouble()) - 40,
top: 84,
width: 80,
child: GestureDetector(
onTap: () => setState(() => sel = i),
child: Column(children: [
Container(
width: 22,
height: 22,
decoration: BoxDecoration(
color: Colors.white,
shape: BoxShape.circle,
border: Border.all(
color: sel == i ? Colors.amber : Colors.indigo, width: 4),
),
),
const SizedBox(height: 30),
Text('${names[i]}\n👥${stations[i].q.length} ⭐${stations[i].rating.toStringAsFixed(1)}',
textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
]),
),
),
for (final q in quests)
if (q.type == 'lost' && q.station == i)
Positioned(
left: sx(i.toDouble()) - 18,
top: 28,
child: GestureDetector(
onTap: () => setState(() => q.progress = 1),
child: const Text('🎒', style: TextStyle(fontSize: 30)),
),
),
],
for (int i = 0; i < trains.length; i++)
Positioned(
left: sx(trains[i].pos) - 24,
top: trains[i].dir > 0 ? 52 : 112,
child: GestureDetector(
onTap: () => _tapTrain(i),
child: Container(
width: 48,
height: 28,
alignment: Alignment.center,
decoration: BoxDecoration(
color: trainColors[i],
borderRadius: BorderRadius.circular(8),
border: Border.all(
color: trains[i].dwell > 0 ? Colors.amber : Colors.transparent,
width: 2),
),
child: Text(
'${quests.any((q) => q.type == 'evader' && q.train == i) ? '🕵️' : '🚆'}${trains[i].load.length}',
style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
),
),
),
),
]);
}),
);
}

Widget _stationTab() {
final s = stations[sel];
return ListView(padding: const EdgeInsets.all(8), children: [
Text('${names[sel]}  •  ⭐ ${s.rating.toStringAsFixed(1)}',
style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
const SizedBox(height: 3),
Text('Waiting ${s.q.length}/${s.cap}  •  Boarded ${s.boarded}',
style: const TextStyle(color: Colors.white70, fontSize: 12)),
const SizedBox(height: 8),
ClipRRect(
borderRadius: BorderRadius.circular(6),
child: LinearProgressIndicator(
value: (s.q.length / s.cap).clamp(0.0, 1.0).toDouble(),
minHeight: 7,
backgroundColor: Colors.white12,
color: s.q.length / s.cap > 0.8 ? Colors.redAccent : Colors.tealAccent,
),
),
const SizedBox(height: 8),
const SizedBox(height: 6),
_tile('🏛️', 'Waiting hall', 'Capacity ${s.cap}', s.hall, 8, cost(60, 1.5, s.hall),
() => s.hall++),
for (int k = 0; k < 3; k++)
_tile(shopNames[k].substring(0, 2), shopNames[k].substring(3),
'+RM ${(s.shops[k] * shopRate[k]).toStringAsFixed(1)}/s (more when crowded)',
s.shops[k], 8, cost(shopBase[k], 1.6, s.shops[k]), () => s.shops[k]++),
]);
}

Widget _trainTab() {
return ListView(padding: const EdgeInsets.all(8), children: [
const Padding(
padding: EdgeInsets.only(bottom: 8),
child: Text(
'Tap a train on the map while it is stopped to make it depart early.',
style: TextStyle(fontSize: 12, color: Colors.white70),
),
),
_tile('🚆', 'Buy train', '${trains.length}/5 trains on the line', trains.length - 1, 4,
cost(250, 2.2, trains.length - 1), () => trains.add(Train())),
_tile('💺', 'Longer trains', 'Seats: $trainCap', capLv, 8, cost(120, 1.6, capLv),
() => capLv++),
_tile('⚡', 'Faster trains', '${speed.toStringAsFixed(2)} stops/s', speedLv, 8,
cost(150, 1.7, speedLv), () => speedLv++),
_tile('🎫', 'Ticket price', '+${fareLv * 15}% fares', fareLv, 10, cost(100, 1.6, fareLv),
() => fareLv++),
_tile('📣', 'Promotion', '+${promoLv * 20}% passengers', promoLv, 10,
cost(120, 1.6, promoLv), () => promoLv++),
for (int i = 0; i < trains.length; i++)
Text('Train ${i + 1}: ${trains[i].load.length}/$trainCap on board • ${trains[i].carried} dropped off',
style: TextStyle(color: trainColors[i], fontSize: 12)),
]);
}

Widget _questTab() {
if (quests.isEmpty) {
return const Center(child: Text('No quests right now… new ones appear soon.'));
}
return ListView(padding: const EdgeInsets.all(8), children: [
for (final q in quests)
Card(
color: const Color(0xFF262A38),
child: ListTile(
title: Text(q.title, style: const TextStyle(fontSize: 14)),
subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text('⏳ ${q.time.ceil()}s   🎁 ${rm(q.reward)}',
style: const TextStyle(fontSize: 12)),
if (q.target > 1)
LinearProgressIndicator(value: q.progress / q.target, minHeight: 4),
]),
),
),
]);
}

Widget _tile(String icon, String title, String desc, int lv, int max, double c,
VoidCallback buy) {
final can = lv < max && money >= c;
return Card(
margin: const EdgeInsets.only(bottom: 6),
color: const Color(0xFF262A38),
child: Padding(
padding: const EdgeInsets.all(10),
child: Row(children: [
Text(icon, style: const TextStyle(fontSize: 24)),
const SizedBox(width: 10),
Expanded(
child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text('$title  •  Lv $lv/$max', style: const TextStyle(fontWeight: FontWeight.bold)),
Text(desc, style: const TextStyle(fontSize: 12, color: Colors.white60)),
const SizedBox(height: 4),
LinearProgressIndicator(value: lv / max, minHeight: 4),
]),
),
const SizedBox(width: 8),
FilledButton(
onPressed: can ? () => _spend(c, buy) : null,
child: Text(lv >= max ? 'MAX' : rm(c).replaceAll('RM ', 'RM')),
),
]),
),
);
}
}