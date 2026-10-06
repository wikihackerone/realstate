import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RealEstateApp());
}

const kStatuses = ['مؤجر', 'شاغر', 'متأخرات'];
final _money = intl.NumberFormat('#,##0.##');
String fmt(num v) => '${_money.format(v)} ج.م';

Color statusColor(String? s) {
  switch (s) {
    case 'مؤجر':
      return const Color(0xFF2E7D32);
    case 'متأخرات':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFFEF6C00);
  }
}

double num0(dynamic v) => (v is num) ? v.toDouble() : 0.0;

class AppCard extends StatelessWidget {
  final Widget child;
  final Clip clipBehavior;
  const AppCard({super.key, required this.child, this.clipBehavior = Clip.none});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        clipBehavior: clipBehavior,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.black.withAlpha(15)),
        ),
        child: child,
      );
}

class RealEstateApp extends StatelessWidget {
  const RealEstateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E85));
    return MaterialApp(
      title: 'إدارة العقارات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF4F7FA),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withAlpha(30)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withAlpha(30)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------
// Database
// ---------------------------------------------------------
class DB {
  static Database? _db;

  static Future<Database> get db async => _db ??= await _init();

  static Future<Database> _init() async {
    final path = p.join(await getDatabasesPath(), 'real_estate.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE properties (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT, address TEXT, tenant_name TEXT, tenant_phone TEXT,
            rent_amount REAL, deposit_amount REAL,
            electricity REAL, water REAL, gas REAL,
            status TEXT, id_card_path TEXT, contract_path TEXT
          )
        ''');
      },
    );
  }

  static Future<List<Map<String, dynamic>>> all() async =>
      (await db).query('properties', orderBy: 'id DESC');

  static Future<int> insert(Map<String, dynamic> d) async =>
      (await db).insert('properties', d);

  static Future<int> update(int id, Map<String, dynamic> d) async =>
      (await db).update('properties', d, where: 'id = ?', whereArgs: [id]);

  static Future<int> delete(int id) async =>
      (await db).delete('properties', where: 'id = ?', whereArgs: [id]);
}

// ---------------------------------------------------------
// Home
// ---------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _query = '';
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DB.all();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PropertyFormScreen(property: item)),
    );
    if (saved == true) {
      await _load();
      _toast(item == null ? 'تمت إضافة العقار' : 'تم تحديث العقار');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العقار'),
        content: Text('هل تريد حذف "${item['name']}" نهائياً؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await DB.delete(item['id'] as int);
      await _load();
      _toast('تم حذف العقار');
    }
  }

  Future<void> _whatsapp(Map<String, dynamic> item, String type) async {
    final phone = (item['tenant_phone'] ?? '').toString();
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      _toast('رقم الهاتف غير مسجل');
      return;
    }
    final total = _total(item);
    final t = item['tenant_name'];
    final n = item['name'];
    final a = fmt(total);
    String msg;
    if (type == 'reminder') {
      msg = 'أهلاً $t، نود تذكيرك بقرب موعد سداد إيجار $n وقيمته الإجمالية $a (شامل المرافق).';
    } else if (type == 'late') {
      msg = 'عزيزي $t، نود إحاطتكم بتأخر سداد مستحقات $n وقيمتها $a. نرجو السداد في أقرب وقت.';
    } else {
      msg = 'شكراً لك $t، تم استلام مبلغ $a الخاص بإيجار ومرافق $n بنجاح.';
    }
    final url = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(msg)}');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) _toast('تعذر فتح WhatsApp');
    } catch (_) {
      _toast('تعذر فتح WhatsApp');
    }
  }

  double _total(Map<String, dynamic> i) =>
      num0(i['rent_amount']) +
      num0(i['electricity']) +
      num0(i['water']) +
      num0(i['gas']);

  List<Map<String, dynamic>> get _filtered {
    return _items.where((i) {
      if (_filter != null && i['status'] != _filter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return '${i['name']} ${i['tenant_name']} ${i['address']}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['العقارات', 'التقارير والإيصالات'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab],
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_tab == 0 ? _propertiesTab() : _reportsTab()),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة عقار'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_work_outlined),
              selectedIcon: Icon(Icons.home_work),
              label: 'العقارات'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'التقارير'),
        ],
      ),
    );
  }

  // ---------------- Properties tab ----------------
  Widget _propertiesTab() {
    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(
              hintText: 'ابحث بالعقار أو المستأجر أو العنوان',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: const Text('الكل'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final s in kStatuses)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: _filter == s,
                    onSelected: (_) => setState(() => _filter = s),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _propertyCard(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final has = _items.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(has ? Icons.search_off : Icons.apartment,
                size: 72, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              has
                  ? 'لا توجد نتائج مطابقة'
                  : 'لا توجد عقارات بعد\nاضغط "إضافة عقار" للبدء',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _propertyCard(Map<String, dynamic> item) {
    final color = statusColor(item['status']);
    final total = _total(item);
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: color.withAlpha(30),
            child: Icon(Icons.apartment, color: color),
          ),
          title: Text('${item['name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                _statusChip(item['status'], color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${item['tenant_name'] ?? ''}',
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          trailing: Text(fmt(total),
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          children: [
            _info(Icons.place_outlined, 'العنوان', '${item['address'] ?? ''}'),
            _info(Icons.phone_outlined, 'الهاتف', '${item['tenant_phone'] ?? ''}'),
            _info(Icons.savings_outlined, 'التأمين',
                fmt(num0(item['deposit_amount']))),
            const Divider(height: 24),
            _info(Icons.payments_outlined, 'الإيجار',
                fmt(num0(item['rent_amount']))),
            _info(Icons.bolt_outlined, 'كهرباء', fmt(num0(item['electricity']))),
            _info(Icons.water_drop_outlined, 'مياه', fmt(num0(item['water']))),
            _info(Icons.local_fire_department_outlined, 'غاز',
                fmt(num0(item['gas']))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('إجمالي المستحق',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(fmt(total),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: color)),
                ],
              ),
            ),
            _images(item),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _waButton('تذكير', Icons.notifications_active,
                      const Color(0xFFF9A825), () => _whatsapp(item, 'reminder')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _waButton('تأخير', Icons.warning_amber_rounded,
                      const Color(0xFFC62828), () => _whatsapp(item, 'late')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _waButton('شكر', Icons.favorite,
                      const Color(0xFF2E7D32), () => _whatsapp(item, 'thanks')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openForm(item),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _delete(item),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String? s, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: c.withAlpha(30), borderRadius: BorderRadius.circular(8)),
        child: Text(s ?? '',
            style: TextStyle(
                color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _info(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black45),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(color: Colors.black54)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _waButton(String label, IconData icon, Color c, VoidCallback onTap) =>
      FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: c,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );

  Widget _images(Map<String, dynamic> item) {
    final entries = <MapEntry<String, String>>[];
    final idp = (item['id_card_path'] ?? '').toString();
    final cp = (item['contract_path'] ?? '').toString();
    if (idp.isNotEmpty && File(idp).existsSync()) {
      entries.add(MapEntry('صورة البطاقة', idp));
    }
    if (cp.isNotEmpty && File(cp).existsSync()) {
      entries.add(MapEntry('صورة العقد', cp));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    child: InteractiveViewer(child: Image.file(File(e.value))),
                  ),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(e.value),
                          width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 4),
                    Text(e.key, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- Reports tab ----------------
  Widget _reportsTab() {
    double rent = 0, utils = 0, deposit = 0, due = 0;
    int rented = 0, vacant = 0, late = 0;
    for (final i in _items) {
      rent += num0(i['rent_amount']);
      utils += num0(i['electricity']) + num0(i['water']) + num0(i['gas']);
      deposit += num0(i['deposit_amount']);
      if (i['status'] == 'متأخرات') {
        due += _total(i);
        late++;
      } else if (i['status'] == 'شاغر') {
        vacant++;
      } else {
        rented++;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E85), Color(0xFF2A8AB8)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إجمالي الإيجارات الشهرية',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(fmt(rent),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('${_items.length} عقار  •  مؤجر $rented  •  شاغر $vacant  •  متأخرات $late',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _stat('المرافق', fmt(utils), Icons.bolt, const Color(0xFFEF6C00)),
          const SizedBox(width: 12),
          _stat('التأمينات', fmt(deposit), Icons.savings, const Color(0xFF00897B)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _stat('متأخرات مستحقة', fmt(due), Icons.warning_amber_rounded,
              const Color(0xFFC62828)),
          const SizedBox(width: 12),
          _stat('عقارات شاغرة', '$vacant', Icons.key, const Color(0xFF6A1B9A)),
        ]),
        const SizedBox(height: 24),
        const Text('إيصالات السداد',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          const Text('لا توجد عقارات لإنشاء إيصالات.',
              style: TextStyle(color: Colors.black54))
        else
          for (final i in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: ListTile(
                  title: Text('${i['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${i['tenant_name']} • ${fmt(_total(i))}'),
                  trailing: IconButton.filledTonal(
                    onPressed: () => _printReceipt(i),
                    icon: const Icon(Icons.picture_as_pdf),
                    tooltip: 'إيصال PDF',
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _stat(String title, String value, IconData icon, Color c) => Expanded(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: c.withAlpha(30),
                    child: Icon(icon, color: c, size: 20)),
                const SizedBox(height: 10),
                Text(title,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c)),
                ),
              ],
            ),
          ),
        ),
      );

  // ---------------- PDF receipt ----------------
  Future<void> _printReceipt(Map<String, dynamic> prop) async {
    try {
      final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
      final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
      final rent = num0(prop['rent_amount']);
      final elec = num0(prop['electricity']);
      final water = num0(prop['water']);
      final gas = num0(prop['gas']);
      final total = rent + elec + water + gas;
      final today = intl.DateFormat('yyyy/MM/dd').format(DateTime.now());

      pw.Widget row(String a, String b, {bool strong = false}) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(a,
                    style: pw.TextStyle(
                        fontWeight: strong ? pw.FontWeight.bold : null)),
                pw.Text(b,
                    style: pw.TextStyle(
                        fontWeight: strong ? pw.FontWeight.bold : null)),
              ],
            ),
          );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          margin: const pw.EdgeInsets.all(24),
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text('إيصال استلام إيجار ومرافق',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text('التاريخ: $today')),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text('العقار: ${prop['name'] ?? ''}'),
              pw.SizedBox(height: 4),
              pw.Text('المستأجر: ${prop['tenant_name'] ?? ''}'),
              pw.SizedBox(height: 4),
              pw.Text('الهاتف: ${prop['tenant_phone'] ?? ''}'),
              pw.SizedBox(height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey500),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(children: [
                  row('الإيجار الشهري', fmt(rent)),
                  row('كهرباء', fmt(elec)),
                  row('مياه', fmt(water)),
                  row('غاز', fmt(gas)),
                  pw.Divider(),
                  row('الإجمالي', fmt(total), strong: true),
                ]),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('توقيع المستلم: ..................'),
                  pw.Text('ختم: ..................'),
                ],
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(
        name: 'receipt_${prop['id']}.pdf',
        onLayout: (PdfPageFormat f) async => doc.save(),
      );
    } catch (e) {
      _toast('تعذر إنشاء الإيصال');
    }
  }
}

// ---------------------------------------------------------
// Add / Edit form (full screen)
// ---------------------------------------------------------
class PropertyFormScreen extends StatefulWidget {
  final Map<String, dynamic>? property;
  const PropertyFormScreen({super.key, this.property});

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _address, _tenant, _phone;
  late final TextEditingController _rent, _deposit, _elec, _water, _gas;
  late String _status;
  String? _idPath, _contractPath;
  bool _saving = false;

  bool get _isEdit => widget.property != null;

  @override
  void initState() {
    super.initState();
    final x = widget.property;
    String s(String k) => (x?[k] ?? '').toString();
    String n(String k) => x == null ? '' : _plain(num0(x[k]));
    _name = TextEditingController(text: s('name'));
    _address = TextEditingController(text: s('address'));
    _tenant = TextEditingController(text: s('tenant_name'));
    _phone = TextEditingController(text: s('tenant_phone'));
    _rent = TextEditingController(text: n('rent_amount'));
    _deposit = TextEditingController(text: n('deposit_amount'));
    _elec = TextEditingController(text: n('electricity'));
    _water = TextEditingController(text: n('water'));
    _gas = TextEditingController(text: n('gas'));
    _status = kStatuses.contains(x?['status']) ? x!['status'] : 'مؤجر';
    _idPath = s('id_card_path').isEmpty ? null : s('id_card_path');
    _contractPath = s('contract_path').isEmpty ? null : s('contract_path');
  }

  String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [
      _name, _address, _tenant, _phone, _rent, _deposit, _elec, _water, _gas
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('التقاط بالكاميرا'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      final img = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (img == null) return null;
      // Copy to permanent app storage (picker paths are temporary).
      final dir = await getApplicationDocumentsDirectory();
      final dest = p.join(
          dir.path, 'img_${DateTime.now().millisecondsSinceEpoch}${p.extension(img.path)}');
      await File(img.path).copy(dest);
      return dest;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر الوصول للصورة')));
      }
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    double d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'tenant_name': _tenant.text.trim(),
      'tenant_phone': _phone.text.trim(),
      'rent_amount': d(_rent),
      'deposit_amount': d(_deposit),
      'electricity': d(_elec),
      'water': d(_water),
      'gas': d(_gas),
      'status': _status,
      'id_card_path': _idPath ?? '',
      'contract_path': _contractPath ?? '',
    };
    if (_isEdit) {
      await DB.update(widget.property!['id'] as int, data);
    } else {
      await DB.insert(data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _field(String label, TextEditingController c,
      {IconData? icon,
      bool number = false,
      bool phone = false,
      bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (phone ? TextInputType.phone : TextInputType.text),
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
            : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Text(t,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _imageTile(String label, IconData icon, String? path,
      ValueChanged<String?> onChanged) {
    final has = path != null && File(path).existsSync();
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final r = await _pick();
          if (r != null) onChanged(r);
        },
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withAlpha(30)),
          ),
          child: has
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(path), fit: BoxFit.cover),
                    ),
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          color: Colors.white,
                          icon: const Icon(Icons.close),
                          onPressed: () => onChanged(null),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 32, color: Colors.black45),
                    const SizedBox(height: 6),
                    Text(label,
                        style: const TextStyle(color: Colors.black54)),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل عقار' : 'إضافة عقار جديد',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _section('بيانات العقار'),
            _field('اسم العقار', _name,
                icon: Icons.apartment, required: true),
            _field('العنوان', _address, icon: Icons.place_outlined),
            DropdownButtonFormField<String>(
              value: _status,
              items: kStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
              decoration: const InputDecoration(
                  labelText: 'حالة العقار', prefixIcon: Icon(Icons.flag_outlined)),
            ),
            const SizedBox(height: 12),
            _section('بيانات المستأجر'),
            _field('اسم المستأجر', _tenant, icon: Icons.person_outline),
            _field('رقم الهاتف (مع رمز الدولة، مثال 2010xxxxxxx)', _phone,
                icon: Icons.phone_outlined, phone: true),
            _section('الماليات'),
            _field('الإيجار الشهري', _rent,
                icon: Icons.payments_outlined, number: true),
            _field('قيمة التأمين', _deposit,
                icon: Icons.savings_outlined, number: true),
            _field('فاتورة الكهرباء', _elec,
                icon: Icons.bolt_outlined, number: true),
            _field('فاتورة المياه', _water,
                icon: Icons.water_drop_outlined, number: true),
            _field('فاتورة الغاز', _gas,
                icon: Icons.local_fire_department_outlined, number: true),
            _section('المرفقات'),
            Row(
              children: [
                _imageTile('بطاقة المستأجر', Icons.badge_outlined, _idPath,
                    (v) => setState(() => _idPath = v)),
                const SizedBox(width: 12),
                _imageTile('صورة العقد', Icons.description_outlined,
                    _contractPath, (v) => setState(() => _contractPath = v)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_isEdit ? 'تحديث' : 'حفظ',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
