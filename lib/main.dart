import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';
import 'dart:async';
const String baseUrl = "http://105.198.235.113:6190";
const String versionUrl =
    "https://raw.githubusercontent.com/MahmoudNasserGomaaAhmed/HR/main/version.json";

// -------------------- WORKMANAGER --------------------
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('pending') ?? [];

    if (list.isEmpty) return Future.value(true);

    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isEmpty) return Future.value(true);
    } catch (_) {
      return Future.value(true);
    }

    String cookie = prefs.getString('cookie') ?? "";
    List<String> success = [];

    for (var item in list) {
      var data = jsonDecode(item);
      try {
        final res = await http.post(
          Uri.parse("$baseUrl/api/resource/Employee%20Checkin"),
          headers: {
            "Content-Type": "application/json",
            "Cookie": cookie,
          },
          body: jsonEncode(data),
        ).timeout(Duration(seconds: 5));
        if (res.statusCode == 200) success.add(item);
      } catch (_) {}
    }

    list.removeWhere((e) => success.contains(e));
    await prefs.setStringList('pending', list);

    return Future.value(true);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(
    "syncTask",
    "syncOfflineData",
    frequency: const Duration(minutes: 15),
  );

  runApp(const MyApp());
}

// -------------------- MAIN APP --------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

// -------------------- LOGIN PAGE --------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final userController = TextEditingController();
  final passController = TextEditingController();
  String message = "";
  bool loading = false;

  double progress = 0;
  bool isDownloading = false;
  CancelToken? cancelToken;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForUpdate();
    });
  }

  Future<void> _loadSavedCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userController.text = prefs.getString('username') ?? "";
    passController.text = prefs.getString('password') ?? "";
  }

  //----------------- UPDATE SYSTEM -----------------
  Future<void> checkForUpdate() async {
    try {
      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        PackageInfo info = await PackageInfo.fromPlatform();
        int currentVersion = int.parse(info.buildNumber);
        if (data["version"] > currentVersion) {
          if (!mounted) return;
          showUpdateDialog(data["url"]);
        }
      }
    } catch (e) {}
  }

  void showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("تحديث جديد"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("يوجد إصدار جديد من التطبيق"),
                const SizedBox(height: 15),
                if (isDownloading)
                  Column(
                    children: [
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 10),
                      Text("${(progress * 100).toStringAsFixed(0)} %"),
                    ],
                  ),
              ],
            ),
            actions: [
              if (!isDownloading)
                TextButton(
                  onPressed: () {
                    startDownload(url, setStateDialog);
                  },
                  child: const Text(".تحديث الآن"),
                ),
              if (isDownloading)
                TextButton(
                  onPressed: () {
                    cancelToken?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text("إلغاء"),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> startDownload(String url, Function setStateDialog) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/update.apk";
      cancelToken = CancelToken();
      setStateDialog(() {
        isDownloading = true;
        progress = 0;
      });
      await Dio().download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (rec, total) {
          if (total != -1) {
            setStateDialog(() {
              progress = rec / total;
            });
          }
        },
      );

      File file = File(filePath);
      if (await file.exists()) {
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("تم التحميل"),
            content: const Text("تم تحميل التحديث بنجاح"),
            actions: [
              TextButton(
                onPressed: () async {
                  final result = await OpenFile.open(filePath);
                  if (result.message.contains("Permission denied")) {
                    final intent = AndroidIntent(
                      action: 'android.settings.MANAGE_UNKNOWN_APP_SOURCES',
                    );
                    await intent.launch();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("من فضلك فعّل السماح بالتثبيت"),
                      ),
                    );
                  }
                },
                child: const Text("تثبيت الآن"),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        message = "⚠️ فشل تحميل التحديث";
      });
    }
  }

  //----------------- LOGIN -----------------
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> login() async {
    setState(() {
      loading = true;
      message = "";
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedUsername = prefs.getString('username');
    String? savedPassword = prefs.getString('password');

    bool online = await hasInternet();
    if (!online) {
      // OFFLINE LOGIN
      if (savedUsername == userController.text.trim() &&
          savedPassword == passController.text.trim()) {
        String? savedEmployee = prefs.getString('employee');
        if (savedEmployee != null) {
          var employee = jsonDecode(savedEmployee);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DashboardPage(cookie: prefs.getString('cookie') ?? "", employee: employee),
            ),
          );
          setState(() => message = "📴 تم تسجيل الدخول بدون نت");
        } else {
          setState(() => message = "❌ لا توجد بيانات لتسجيل الدخول Offline");
        }
      } else {
        setState(() => message = "❌         البيانات غير صحيحة");
      }
      setState(() => loading = false);
      return;
    }

    // ONLINE LOGIN
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/method/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "usr": userController.text.trim(),
          "pwd": passController.text.trim(),
        }),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        await prefs.setString('username', userController.text.trim());
        await prefs.setString('password', passController.text.trim());

        String rawCookie = response.headers['set-cookie'] ?? "";
        String sessionCookie = rawCookie.split(';').first;
        await prefs.setString('cookie', sessionCookie);

        final empResponse = await http.get(
          Uri.parse(
              "$baseUrl/api/resource/Employee?filters=[[\"user_id\",\"=\",\"${userController.text.trim()}\"]]"
              "&fields=[\"name\",\"employee_name\",\"designation\",\"department\",\"employee_number\",\"user_id\"]"),
          headers: {"Cookie": sessionCookie},
        );

        var empData = jsonDecode(empResponse.body);

        if (empData['data'] != null && empData['data'].isNotEmpty) {
          var employee = empData['data'][0];
          await prefs.setString('employee', jsonEncode(employee));

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardPage(cookie: sessionCookie, employee: employee),
            ),
          );
        } else {
          setState(() => message = "❌ لا يوجد موظف مرتبط بهذا المستخدم");
        }
      } else {
        setState(() => message = "❌ بيانات غير صحيحة");
      }
    } catch (e) {
      setState(() => message = "⚠️ خطأ اتصال بالسيرفر");
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.blueGrey.shade50,
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 80, color: Colors.blue),
                    const SizedBox(height: 15),
                    const Text(
                      "تسجيل الدخول",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: userController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person),
                        labelText: "اسم المستخدم",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: passController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.lock),
                        labelText: "كلمة المرور",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: loading ? null : login,
                      icon: loading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.login),
                      label: const Text("تسجيل الدخول", style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- DASHBOARD PAGE --------------------
class DashboardPage extends StatefulWidget {
  final Map employee;
  final String cookie;
  const DashboardPage({super.key, required this.employee, required this.cookie});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String message = "جاهز لتسجيل الحضور";
  bool loading = false;

  @override
  void initState() {
    super.initState();
    startNetworkListener();
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => message = "❌ خدمة الموقع معطلة");
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => message = "❌ رفض إذن الموقع");
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => message = "❌ إذن الموقع مرفوض نهائياً");
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
  }

  Future<void> saveOffline(Map data) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('pending') ?? [];
    list.add(jsonEncode(data));
    await prefs.setStringList('pending', list);
  }

  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> syncData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList('pending') ?? [];
    if (list.isEmpty) return;

    bool online = await hasInternet();
    if (!online) return;

    List<String> success = [];
    for (var item in list) {
      var data = jsonDecode(item);
      try {
        final res = await http.post(
          Uri.parse("$baseUrl/api/resource/Employee%20Checkin"),
          headers: {
            "Content-Type": "application/json",
            "Cookie": widget.cookie,
          },
          body: jsonEncode(data),
        ).timeout(Duration(seconds: 5));
        if (res.statusCode == 200) success.add(item);
      } catch (e) {}
    }

    list.removeWhere((e) => success.contains(e));
    await prefs.setStringList('pending', list);

    if (success.isNotEmpty) setState(() => message = "🔄 تم المزامنة (${success.length})");
  }

  Future<void> checkInOut(String status) async {
    setState(() {
      loading = true;
      message = "جاري معالجة العملية...";
    });

    Position? pos = await _getCurrentLocation();
    if (pos == null) {
      setState(() => loading = false);
      return;
    }

    Map data = {
      "employee": widget.employee['name'],
      "log_type": status == "Present" ? "IN" : "OUT",
      "time": DateTime.now().toIso8601String(),
      "device_id": "mobile",
      "latitude": pos.latitude,
      "longitude": pos.longitude,
    };

    bool online = await hasInternet();

    if (online) {
      try {
        final res = await http.post(
          Uri.parse("$baseUrl/api/resource/Employee%20Checkin"),
          headers: {
            "Content-Type": "application/json",
            "Cookie": widget.cookie,
          },
          body: jsonEncode(data),
        ).timeout(Duration(seconds: 5));
        if (res.statusCode == 200) {
          setState(() => message =
              "✅ تم تسجيل ${status == "Present" ? "الحضور" : "الانصراف"} بنجاح");
        } else {
          await saveOffline(data);
          setState(() => message = "📴 تم الحفظ Offline (خطأ في السيرفر)");
        }
      } catch (e) {
        await saveOffline(data);
        setState(() => message = "📴 تم الحفظ Offline (  السيرفر)");
      }
    } else {
      await saveOffline(data);
      setState(() => message = "📴 تم الحفظ  (بدون نت)");
    }

    await syncData();
    setState(() => loading = false);
  }

  Widget _employeeInfoCard(IconData icon, String title, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: Text(value.isNotEmpty ? value : "-"),
      ),
    );
  }

  Future<void> logout() async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  StreamSubscription? sub;
  void startNetworkListener() {
    sub = Stream.periodic(const Duration(seconds: 5)).listen((_) async {
      bool online = await hasInternet();
      if (online) {
        await syncData();
      }
    });
  }
  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          title: Text(
              "مرحبا ${widget.employee['employee_name'] ?? widget.employee['name']}"),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: logout,
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () async {
                setState(() => message = "🔄 جاري المزامنة...");
                await syncData();
              },
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.blueGrey.shade50,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _employeeInfoCard(Icons.person, "الاسم",
                      widget.employee['employee_name'] ?? ""),
                  _employeeInfoCard(Icons.work, "الوظيفة",
                      widget.employee['designation'] ?? ""),
                  _employeeInfoCard(Icons.apartment, "القسم",
                      widget.employee['department'] ?? ""),
                  _employeeInfoCard(Icons.email, "البريد الإلكتروني",
                      widget.employee['user_id'] ?? ""),
                  _employeeInfoCard(Icons.numbers, "رقم الموظف",
                      widget.employee['employee_number'] ?? ""),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: loading ? null : () => checkInOut("Present"),
                    icon: const Icon(Icons.fingerprint, size: 30),
                    label: const Text("تسجيل حضور",
                        style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: loading ? null : () => checkInOut("Left"),
                    icon: const Icon(Icons.fingerprint, size: 30),
                    label: const Text("تسجيل انصراف",
                        style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}