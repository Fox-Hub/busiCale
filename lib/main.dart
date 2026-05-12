import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. タイムゾーンの初期化
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

  // 2. 通知の初期化設定
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 保存されている設定を読み込み
  final prefs = await SharedPreferences.getInstance();

  // テーマモードの復元
  final savedThemeIndex = prefs.getInt('theme_mode');
  if (savedThemeIndex != null) {
    themeModeNotifier.value = ThemeMode.values[savedThemeIndex];
  }

  // テーマカラーの復元
  final savedColorValue = prefs.getInt('theme_color');
  if (savedColorValue != null) {
    themeColorNotifier.value = Color(savedColorValue);
  }

  runApp(const BusinessCalendarApp());
}

ValueNotifier<Color> themeColorNotifier = ValueNotifier(Colors.blueAccent);
ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

class BusinessCalendarApp extends StatelessWidget {
  const BusinessCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ja', 'JP'),
              themeMode: mode,
              // ライトテーマ
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: color,
                brightness: Brightness.light,
              ),
              // ダークテーマ
              darkTheme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: color,
                brightness: Brightness.dark,
              ),
              home: const CalendarScreen(),
            );
          },
        );
      },
    );
  }
}

// 個別の休暇データ
class HolidayData {
  bool isHoliday;
  List<String> tasks;
  String address;
  String phoneNumber;
  String contactPerson;

  HolidayData({
    this.isHoliday = false,
    List<String>? tasks,
    this.address = '',
    this.phoneNumber = '',
    this.contactPerson = '',
  }) : tasks = tasks ?? [];

  Map<String, dynamic> toJson() => {
    'isHoliday': isHoliday,
    'tasks': tasks,
    'address': address,
    'phoneNumber': phoneNumber,
    'contactPerson': contactPerson,
  };

  factory HolidayData.fromJson(Map<String, dynamic> json) {
    return HolidayData(
      isHoliday: json['isHoliday'] ?? false,
      tasks: json['tasks'] != null ? List<String>.from(json['tasks']) : [],
      address: json['address'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      contactPerson: json['contactPerson'] ?? '',
    );
  }
}

class FixedHoliday {
  int month;
  int day;
  String title;
  FixedHoliday({required this.month, required this.day, required this.title});

  Map<String, dynamic> toJson() => {'month': month, 'day': day, 'title': title};
  factory FixedHoliday.fromJson(Map<String, dynamic> json) => FixedHoliday(
    month: json['month'],
    day: json['day'],
    title: json['title'],
  );
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  final DateTime _today = DateTime.now();
  final PageController _pageController = PageController();
  final TextEditingController _milestoneTitleController =
      TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _milestones = [];

  bool _includeWeekends = false;
  Map<DateTime, HolidayData> _holidayConfigs = {};
  List<FixedHoliday> _fixedHolidays = [];

  final Map<DateTime, String> _japaneseHolidays2026 = {
    DateTime(2026, 1, 1): "元日",
    DateTime(2026, 1, 12): "成人の日",
    DateTime(2026, 2, 11): "建国記念の日",
    DateTime(2026, 2, 23): "天皇誕生日",
    DateTime(2026, 3, 20): "春分の日",
    DateTime(2026, 4, 29): "昭和の日",
    DateTime(2026, 5, 3): "憲法記念日",
    DateTime(2026, 5, 4): "みどりの日",
    DateTime(2026, 5, 5): "こどもの日",
    DateTime(2026, 5, 6): "振替休日",
    DateTime(2026, 7, 20): "海の日",
    DateTime(2026, 8, 11): "山の日",
    DateTime(2026, 9, 21): "敬老の日",
    DateTime(2026, 9, 22): "国民の休日",
    DateTime(2026, 9, 23): "秋分の日",
    DateTime(2026, 10, 12): "スポーツの日",
    DateTime(2026, 11, 3): "文化の日",
    DateTime(2026, 11, 23): "勤労感謝の日",
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> dataToSave = {};
    _holidayConfigs.forEach(
      (key, value) =>
          dataToSave[key.toIso8601String()] = jsonEncode(value.toJson()),
    );
    await prefs.setString('holiday_configs', jsonEncode(dataToSave));
    await prefs.setBool('include_weekends', _includeWeekends);
    List<String> fixedList = _fixedHolidays
        .map((e) => jsonEncode(e.toJson()))
        .toList();
    await prefs.setStringList('fixed_holidays_v2', fixedList);
  }

  Future<void> _saveMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedData = jsonEncode(
      _milestones.map((m) {
        return {
          'title': m['title'],
          'date': (m['date'] as DateTime).toIso8601String(),
          'isRecurring': m['isRecurring'] ?? false,
        };
      }).toList(),
    );
    await prefs.setString('saved_milestones', encodedData);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _includeWeekends = prefs.getBool('include_weekends') ?? false;
      List<String>? fixedJsonList = prefs.getStringList('fixed_holidays_v2');
      if (fixedJsonList != null) {
        _fixedHolidays = fixedJsonList
            .map((e) => FixedHoliday.fromJson(jsonDecode(e)))
            .toList();
      }
      String? jsonString = prefs.getString('holiday_configs');
      if (jsonString != null) {
        Map<String, dynamic> savedData = jsonDecode(jsonString);
        _holidayConfigs = savedData.map(
          (k, v) =>
              MapEntry(DateTime.parse(k), HolidayData.fromJson(jsonDecode(v))),
        );
      }
      String? milestonesJson = prefs.getString('saved_milestones');
      if (milestonesJson != null) {
        List<dynamic> decoded = jsonDecode(milestonesJson);
        _milestones = decoded
            .map(
              (m) => {
                'title': m['title'],
                'date': DateTime.parse(m['date']),
                'isRecurring': m['isRecurring'] ?? false,
              },
            )
            .toList();
      }
    });
  }

  bool _isOffDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_japaneseHolidays2026.containsKey(date)) return true;
    if (_fixedHolidays.any(
      (fh) => fh.month == date.month && fh.day == date.day,
    ))
      return true;
    final config = _holidayConfigs[date];
    if (config != null && config.isHoliday == true) return true;
    if (!_includeWeekends) {
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday)
        return true;
    }
    return false;
  }

  bool _isRedLetterHoliday(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_japaneseHolidays2026.containsKey(date)) return true;
    return _fixedHolidays.any(
      (fh) => fh.month == date.month && fh.day == date.day,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    DateTime lastDayOfMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
    );

    List<DateTime> businessDays = [];
    for (int i = 0; i < lastDayOfMonth.day; i++) {
      DateTime day = firstDayOfMonth.add(Duration(days: i));
      if (!_isOffDay(day)) businessDays.add(day);
    }

    DateTime lastBD = businessDays.isNotEmpty
        ? businessDays.last
        : lastDayOfMonth;
    DateTime todayDate = DateTime(_today.year, _today.month, _today.day);
    int count = businessDays.where((day) => day.isAfter(todayDate)).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).scaffoldBackgroundColor,
                  ]
                : [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTopCards(count, lastBD),
              Expanded(flex: 3, child: _buildCalendarCard(lastBD)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.list_alt,
                      size: 18,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '予定一覧',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.blueGrey[200] : Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(flex: 2, child: _buildBusinessDayList(businessDays)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessDayList(List<DateTime> businessDays) {
    if (businessDays.isEmpty) return const Center(child: Text('営業日はありません'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todayDate = DateTime(_today.year, _today.month, _today.day);
    int todayIndex = businessDays.indexWhere((day) {
      final dayDate = DateTime(day.year, day.month, day.day);
      return dayDate.isAtSameMomentAs(todayDate) || dayDate.isAfter(todayDate);
    });
    if (todayIndex == -1) todayIndex = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        double offset = todayIndex * 98.0;
        _scrollController.jumpTo(offset);
      }
    });

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      itemCount: businessDays.length,
      itemBuilder: (context, index) {
        DateTime day = businessDays[index];
        bool isToday = isSameDay(day, _today);
        final dateKey = DateTime(day.year, day.month, day.day);
        final config = _holidayConfigs[dateKey];

        return Dismissible(
          key: ValueKey(dateKey),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            if (config == null ||
                (config.tasks.isEmpty &&
                    config.address.isEmpty &&
                    config.phoneNumber.isEmpty &&
                    config.contactPerson.isEmpty))
              return false;
            setState(() => _holidayConfigs.remove(dateKey));
            await _saveData();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${day.month}/${day.day} の予定をクリアしました')),
            );
            return false;
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(right: 20),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.delete_sweep, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isToday
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withOpacity(0.3)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: isToday
                    ? Colors.blueAccent.withOpacity(0.5)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第${index + 1}営業日',
                        style: TextStyle(
                          color: Colors.blueGrey[300],
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${day.month}/${day.day}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        ['', '月', '火', '水', '木', '金', '土', '日'][day.weekday],
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey[600],
                        ),
                      ),
                    ],
                  ),
                  const VerticalDivider(
                    width: 24,
                    thickness: 1,
                    indent: 4,
                    endIndent: 4,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (config != null && config.tasks.isNotEmpty)
                          ...config.tasks.map(
                            (task) => Text(
                              '・$task',
                              style: const TextStyle(fontSize: 14),
                            ),
                          )
                        else
                          Text(
                            'タスクなし',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (config != null &&
                            (config.contactPerson.isNotEmpty ||
                                config.phoneNumber.isNotEmpty ||
                                config.address.isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if (config.contactPerson.isNotEmpty)
                                  _buildSmallInfo(
                                    Icons.person,
                                    config.contactPerson,
                                  ),
                                if (config.phoneNumber.isNotEmpty)
                                  _buildSmallInfo(
                                    Icons.phone,
                                    config.phoneNumber,
                                  ),
                                if (config.address.isNotEmpty)
                                  _buildSmallInfo(Icons.place, config.address),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isToday)
                    const Icon(
                      Icons.push_pin,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _focusedDay = DateTime(
                    _focusedDay.year,
                    _focusedDay.month - 1,
                  ),
                ),
              ),
              Text(
                '${_focusedDay.year}年 ${_focusedDay.month}月',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _focusedDay = DateTime(
                    _focusedDay.year,
                    _focusedDay.month + 1,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 28),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    includeWeekends: _includeWeekends,
                    fixedHolidays: _fixedHolidays,
                    onChanged: (newInclude, newFixed) {
                      setState(() {
                        _includeWeekends = newInclude;
                        _fixedHolidays = newFixed;
                      });
                      _saveData();
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  int _currentPageIndex = 0;
  Widget _buildTopCards(int count, DateTime lastBD) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 220,
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentPageIndex = index),
          children: [
            _buildBaseCard(
              title: '残り営業日',
              child: _buildCountContent(
                '',
                '$count',
                '最終営業日: ${lastBD.month}/${lastBD.day}',
                Colors.blueAccent,
              ),
            ),
            ..._milestones.asMap().entries.map((entry) {
              int index = entry.key;
              var milestone = entry.value;
              DateTime targetDate = milestone['isRecurring'] == true
                  ? _adjustToBusinessDay(
                      DateTime(
                        _focusedDay.year,
                        _focusedDay.month,
                        milestone['date'].day,
                      ),
                    )
                  : milestone['date'];
              final diff =
                  DateTime(targetDate.year, targetDate.month, targetDate.day)
                      .difference(
                        DateTime(_today.year, _today.month, _today.day),
                      )
                      .inDays;
              Color cardColor = diff == 0
                  ? Colors.redAccent
                  : (diff > 0 ? Colors.orangeAccent : Colors.grey);
              return _buildBaseCard(
                title: milestone['title'],
                headerColor: cardColor,
                onLongPress: () => _showEditMilestoneModal(index),
                onDelete: () {
                  setState(() => _milestones.removeAt(index));
                  _saveMilestones();
                },
                child: _buildCountContent(
                  milestone['title'],
                  diff == 0 ? '当日' : '${diff.abs()}',
                  diff == 0
                      ? '本日の予定です'
                      : (diff > 0
                            ? '設定期限日: ${targetDate.month}/${targetDate.day}'
                            : '${diff.abs()} 日経過'),
                  cardColor,
                ),
              );
            }),
            _buildAddCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCountContent(
    String title,
    String mainText,
    String subText,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          mainText,
          style: TextStyle(
            fontSize: 54,
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: -2,
          ),
        ),
        Text(
          subText,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAddCard() {
    return GestureDetector(
      onTap: _showAddMilestoneModal,
      child: _buildBaseCard(
        title: '重要日を追加',
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 48, color: Colors.blueAccent),
            Text(
              '重要日を追加',
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBaseCard({
    required String title,
    required Widget child,
    Color headerColor = Colors.blueAccent,
    VoidCallback? onLongPress,
    VoidCallback? onDelete,
    VoidCallback? onEdit,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.05,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 32,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (onEdit != null) // ★ 編集ボタン
                    GestureDetector(
                      onTap: onEdit,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.edit, color: Colors.white, size: 16),
                      ),
                    ),
                  if (onDelete != null)
                    GestureDetector(
                      onTap: onDelete,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: Center(child: child)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(DateTime lastBD) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    DateTime? activeCardDate;
    if (_currentPageIndex > 0 && _currentPageIndex <= _milestones.length) {
      var m = _milestones[_currentPageIndex - 1];
      activeCardDate = m['isRecurring'] == true
          ? _adjustToBusinessDay(
              DateTime(_focusedDay.year, _focusedDay.month, m['date'].day),
            )
          : m['date'];
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: TableCalendar(
        firstDay: DateTime(2026, 1, 1),
        lastDay: DateTime(2026, 12, 31),
        rowHeight: 45,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        focusedDay: _focusedDay,
        currentDay: _today,
        headerVisible: false,
        onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
        selectedDayPredicate: (day) => isSameDay(day, activeCardDate ?? lastBD),
        onDaySelected: (selectedDay, focusedDay) =>
            _showDetailModal(context, selectedDay),
        calendarBuilders: CalendarBuilders(
          prioritizedBuilder: (context, day, focusedDay) {
            if (day.month != focusedDay.month) return const SizedBox.shrink();
            final dateKey = DateTime(day.year, day.month, day.day);
            final config = _holidayConfigs[dateKey];
            final bool isSelected = isSameDay(day, activeCardDate ?? lastBD);
            final bool isToday = isSameDay(day, _today);

            BoxDecoration? cellDecoration;
            TextStyle textStyle = TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 14,
            );

            if (isSelected) {
              cellDecoration = BoxDecoration(
                color: activeCardDate != null
                    ? Colors.orange
                    : Colors.blueAccent,
                shape: BoxShape.circle,
              );
              textStyle = const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              );
            } else if (isToday) {
              cellDecoration = BoxDecoration(
                color: Colors.blue.withOpacity(isDark ? 0.3 : 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blueAccent),
              );
              textStyle = const TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (_isRedLetterHoliday(day)) {
              textStyle = TextStyle(
                color: isDark ? Colors.redAccent[100] : Colors.redAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (day.weekday == DateTime.saturday) {
              textStyle = TextStyle(
                color: isDark ? Colors.lightBlueAccent : Colors.blueAccent,
                fontWeight: FontWeight.bold,
              );
            } else if (day.weekday == DateTime.sunday || _isOffDay(day)) {
              textStyle = TextStyle(
                color: isDark ? Colors.redAccent[100] : Colors.redAccent,
              );
            }

            return Stack(
              alignment: Alignment.center,
              children: [
                if (cellDecoration != null)
                  Container(width: 34, height: 34, decoration: cellDecoration),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${day.day}', style: textStyle),
                    if (config != null && config.tasks.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showDetailModal(BuildContext context, DateTime selectedDay) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateKey = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    _holidayConfigs.putIfAbsent(dateKey, () => HolidayData());
    final config = _holidayConfigs[dateKey]!;
    List<String> tempTasks = List.from(config.tasks);
    final taskController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${selectedDay.month}/${selectedDay.day} の予定',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextField(
                  controller: taskController,
                  decoration: const InputDecoration(hintText: '予定を入力'),
                  onSubmitted: (val) {
                    if (val.isNotEmpty) {
                      setModalState(() => tempTasks.add(val));
                      taskController.clear();
                    }
                  },
                ),
                ...tempTasks.asMap().entries.map(
                  (e) => ListTile(
                    title: Text(e.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () =>
                          setModalState(() => tempTasks.removeAt(e.key)),
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('この日を休日に設定'),
                  value: config.isHoliday,
                  onChanged: (val) =>
                      setModalState(() => config.isHoliday = val),
                ),
                _buildDetailInput(
                  icon: Icons.person_outline,
                  hint: '担当者名',
                  initialValue: config.contactPerson,
                  onChanged: (val) => config.contactPerson = val,
                ),
                _buildDetailInput(
                  icon: Icons.phone_outlined,
                  hint: '電話番号',
                  initialValue: config.phoneNumber,
                  keyboardType: TextInputType.phone,
                  onChanged: (val) => config.phoneNumber = val,
                ),
                _buildDetailInput(
                  icon: Icons.map_outlined,
                  hint: '住所',
                  initialValue: config.address,
                  onChanged: (val) => config.address = val,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => config.tasks = tempTasks);
                      _saveData();
                      Navigator.pop(context);
                    },
                    child: const Text('保存して反映'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailInput({
    required IconData icon,
    required String hint,
    required String initialValue,
    required Function(String) onChanged,
    TextInputType? keyboardType,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: TextEditingController(text: initialValue)
          ..selection = TextSelection.collapsed(offset: initialValue.length),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 20),
          hintText: hint,
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSmallInfo(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  DateTime _adjustToBusinessDay(DateTime date) {
    DateTime adjusted = date;
    while (adjusted.weekday == DateTime.saturday ||
        adjusted.weekday == DateTime.sunday ||
        _isRedLetterHoliday(adjusted)) {
      adjusted = adjusted.subtract(const Duration(days: 1));
    }
    return adjusted;
  }

  void _showAddMilestoneModal() {
    _milestoneTitleController.clear();
    DateTime tempDate = DateTime(2026, DateTime.now().month, 25);
    bool isRecurring = false;
    bool isNotify = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _milestoneTitleController,
                decoration: const InputDecoration(labelText: "タイトル"),
              ),
              SwitchListTile(
                title: const Text("毎月繰り返す"),
                value: isRecurring,
                onChanged: (v) => setModalState(() => isRecurring = v),
              ),
              SwitchListTile(
                title: const Text("当日の9時に通知"),
                value: isNotify,
                onChanged: (v) => setModalState(() => isNotify = v),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_milestoneTitleController.text.isNotEmpty) {
                    setState(
                      () => _milestones.add({
                        'title': _milestoneTitleController.text,
                        'date': isRecurring
                            ? tempDate
                            : _adjustToBusinessDay(tempDate),
                        'isRecurring': isRecurring,
                        'isNotify': isNotify,
                      }),
                    );

                    // 通知がONなら予約
                    if (isNotify) {
                      scheduleNotification(
                        _milestones.length, // IDとしてインデックスを使用（重複しないように管理が必要）
                        _milestoneTitleController.text,
                        tempDate,
                      );
                    }
                    _saveMilestones();
                    Navigator.pop(context);
                  }
                },
                child: const Text("保存"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditMilestoneModal(int index) {
    final milestone = _milestones[index];
    _milestoneTitleController.text = milestone['title'];
    DateTime selectedDate = milestone['date'];
    bool isRecurring = milestone['isRecurring'] ?? false;
    bool isNotify = milestone['isNotify'] ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 24,
            right: 24,
            top: 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '重要日の編集',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _milestoneTitleController,
                decoration: const InputDecoration(labelText: "タイトル"),
              ),
              ListTile(
                title: Text(
                  "日付: ${selectedDate.year}/${selectedDate.month}/${selectedDate.day}",
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 12, 31),
                  );
                  if (picked != null)
                    setModalState(() => selectedDate = picked);
                },
              ),
              SwitchListTile(
                title: const Text('毎月繰り返す'),
                value: isRecurring,
                onChanged: (val) => setModalState(() => isRecurring = val),
              ),
              SwitchListTile(
                title: const Text("当日の9時に通知"),
                value: isNotify,
                onChanged: (v) => setModalState(() => isNotify = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_milestoneTitleController.text.isNotEmpty) {
                      final newMilestone = {
                        'title': _milestoneTitleController.text,
                        'date': selectedDate,
                        'isRecurring': isRecurring,
                        'isNotify': isNotify,
                      };

                      setState(() => _milestones.add(newMilestone));
                      _saveMilestones();

                      // 通知がONなら予約
                      if (isNotify) {
                        scheduleNotification(
                          _milestones.length, // IDとしてインデックスを使用（重複しないように管理が必要）
                          _milestoneTitleController.text,
                          selectedDate,
                        );
                      }
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('変更を保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> scheduleNotification(int id, String title, DateTime date) async {
  await flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    '重要日の通知',
    title,
    tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      9, // 9時
      0,
    ),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'milestone_channel',
        '重要日の通知',
        channelDescription: '設定された重要日の当日に通知します',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time, // 繰り返し設定が必要な場合はここを調整
  );
}

class SettingsScreen extends StatefulWidget {
  final bool includeWeekends;
  final List<FixedHoliday> fixedHolidays;
  final Function(bool, List<FixedHoliday>) onChanged;
  const SettingsScreen({
    super.key,
    required this.includeWeekends,
    required this.fixedHolidays,
    required this.onChanged,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _tempInclude;
  late List<FixedHoliday> _tempFixed;

  @override
  void initState() {
    super.initState();
    _tempInclude = widget.includeWeekends;
    _tempFixed = List.from(widget.fixedHolidays);
  }

  // 設定を保存する関数
  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アプリ設定')),
      body: ListView(
        children: [
          _buildSectionTitle('基本設定'),
          _buildGroup([
            SwitchListTile(
              title: const Text('土日を営業日に含める'),
              value: _tempInclude,
              onChanged: (val) {
                setState(() => _tempInclude = val);
                widget.onChanged(_tempInclude, _tempFixed);
              },
            ),
          ]),
          _buildSectionTitle('固定休日'),
          _buildGroup(
            _tempFixed.isEmpty
                ? [
                    const ListTile(
                      title: Text(
                        '登録された固定休日はありません',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                  ]
                : _tempFixed.asMap().entries.map((entry) {
                    return ListTile(
                      leading: const Icon(
                        Icons.event_available_rounded,
                        color: Colors.blueAccent,
                      ),
                      title: Text(entry.value.title),
                      subtitle: Text(
                        '${entry.value.month}月${entry.value.day}日',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        onPressed: () {
                          setState(() => _tempFixed.removeAt(entry.key));
                          widget.onChanged(_tempInclude, _tempFixed);
                        },
                      ),
                    );
                  }).toList(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => _showAddFixedHolidayDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('固定休日を追加'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          _buildSectionTitle('デザイン設定'),
          _buildGroup([
            ValueListenableBuilder(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) => SwitchListTile(
                title: const Text('ダークモード'),
                value: mode == ThemeMode.dark,
                onChanged: (val) {
                  final newMode = val ? ThemeMode.dark : ThemeMode.light;
                  themeModeNotifier.value = newMode;
                  _saveSetting('theme_mode', newMode.index);
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  void _showAddFixedHolidayDialog() {
    DateTime selectedDate = DateTime.now();
    String title = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('固定休日を追加'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '休日の名前',
                      hintText: '例：創立記念日',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => title = val,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '日付を選択',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height: 300,
                    child: CalendarDatePicker(
                      initialDate: selectedDate,
                      firstDate: DateTime(2026, 1, 1),
                      lastDate: DateTime(2026, 12, 31),
                      onDateChanged: (date) {
                        setDialogState(() => selectedDate = date);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                if (title.isNotEmpty) {
                  setState(() {
                    _tempFixed.add(
                      FixedHoliday(
                        month: selectedDate.month,
                        day: selectedDate.day,
                        title: title,
                      ),
                    );
                  });
                  widget.onChanged(_tempInclude, _tempFixed);
                  Navigator.pop(context);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 13, color: Colors.grey),
    ),
  );
  Widget _buildGroup(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      border: Border.symmetric(
        horizontal: BorderSide(color: Theme.of(context).dividerColor),
      ),
    ),
    child: Column(children: children),
  );
}
