import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const AegisApp());
}

class AegisApp extends StatefulWidget {
  const AegisApp({super.key});

  @override
  State<AegisApp> createState() => _AegisAppState();
}

class _AegisAppState extends State<AegisApp> {
  bool isAccessibilityMode = false;
  String currentUserName = "Administrator";
  String currentUserRole = "ADMIN";
  String currentUserCondition = "NONE";

  void toggleAccessibility(bool value) {
    setState(() => isAccessibilityMode = value);
  }

  void switchUser(String name, String role, String condition, bool acc) {
    setState(() {
      currentUserName = name;
      currentUserRole = role;
      currentUserCondition = condition;
      isAccessibilityMode = acc;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A.E.G.I.S. Integrated Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: isAccessibilityMode ? Colors.black : const Color(0xFF0A0E14),
        primaryColor: const Color(0xFF00E5FF),
        cardColor: const Color(0xFF151921),
        textTheme: isAccessibilityMode 
            ? const TextTheme(bodyLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), bodyMedium: TextStyle(fontSize: 22))
            : const TextTheme(bodyLarge: TextStyle(fontSize: 16), bodyMedium: TextStyle(fontSize: 14)),
        useMaterial3: true,
      ),
      home: MainNavigation(
        userName: currentUserName,
        userRole: currentUserRole,
        userCondition: currentUserCondition,
        isAccessibilityMode: isAccessibilityMode, 
        onAccessibilityToggle: toggleAccessibility,
        onUserSwitch: switchUser,
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final String userName;
  final String userRole;
  final String userCondition;
  final bool isAccessibilityMode;
  final Function(bool) onAccessibilityToggle;
  final Function(String, String, String, bool) onUserSwitch;

  const MainNavigation({
    super.key, 
    required this.userName, 
    required this.userRole,
    required this.userCondition,
    required this.isAccessibilityMode, 
    required this.onAccessibilityToggle,
    required this.onUserSwitch,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(
        isAccessibilityMode: widget.isAccessibilityMode, 
        userName: widget.userName, 
        userCondition: widget.userCondition,
        userRole: widget.userRole,
      ),
      const HistoryScreen(),
      SecurityScreen(onUserSwitch: widget.onUserSwitch),
      SettingsScreen(isAccessibilityMode: widget.isAccessibilityMode, onAccessibilityToggle: widget.onAccessibilityToggle),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF151921),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.blueGrey.withOpacity(0.5),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'HUB'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'HISTORY'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_rounded), label: 'PROFILES'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_suggest_rounded), label: 'SETTINGS'),
        ],
      ),
    );
  }
}

// --- HUB SCREEN ---
class DashboardScreen extends StatefulWidget {
  final bool isAccessibilityMode;
  final String userName;
  final String userCondition;
  final String userRole;
  const DashboardScreen({
    super.key, 
    required this.isAccessibilityMode, 
    required this.userName, 
    required this.userCondition,
    required this.userRole,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool isLightOn = false;
  bool isDoorLocked = true;
  bool isFanOn = false;
  double temperature = 24.5;
  bool isBrainOnline = false;
  final String backendUrl = "http://10.0.2.2:8080";
  final String wsUrl = "ws://10.0.2.2:8080/ws/house";
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _connectWS();
  }

  void _connectWS() {
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        final msg = json.decode(message);
        if (msg['type'] == 'INIT') {
          _updateFullState(msg['data']);
        } else if (msg['type'] == 'UPDATE') {
          _updateSingleDevice(msg['device'], msg['data']);
        }
        if (mounted) setState(() => isBrainOnline = true);
      }, onError: (err) {
        if (mounted) setState(() => isBrainOnline = false);
        Future.delayed(const Duration(seconds: 3), _connectWS);
      }, onDone: () {
        if (mounted) setState(() => isBrainOnline = false);
        Future.delayed(const Duration(seconds: 3), _connectWS);
      });
    } catch (e) {
      if (mounted) setState(() => isBrainOnline = false);
      Future.delayed(const Duration(seconds: 3), _connectWS);
    }
  }

  void _updateFullState(dynamic data) {
    if (mounted) {
      setState(() {
        isLightOn = data['light']['status'] == "ON";
        isDoorLocked = data['door']['status'] == "LOCKED";
        isFanOn = data['fan'] != null ? data['fan']['status'] == "ON" : false;
        temperature = (data['temp'] as num).toDouble();
      });
    }
  }

  void _updateSingleDevice(String device, dynamic data) {
    if (mounted) {
      setState(() {
        if (device == "light") isLightOn = data['status'] == "ON";
        if (device == "door") isDoorLocked = data['status'] == "LOCKED";
        if (device == "fan") isFanOn = data['status'] == "ON";
      });
    }
  }

  bool _hasPermission() {
    return widget.userRole == "ADMIN" || widget.userRole == "RESPONDER";
  }

  void _showAccessDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("ACCESS DENIED: RESTRICTED USER"),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleDevice(String deviceId) async {
    if (!_hasPermission()) {
      _showAccessDenied();
      return;
    }
    try {
      await http.post(Uri.parse("$backendUrl/toggle/$deviceId"));
    } catch (e) {
      debugPrint("Toggle failed: $e");
    }
  }

  Future<void> _triggerSOS() async {
    if (!_hasPermission()) {
      _showAccessDenied();
      return;
    }
    try {
      await http.post(Uri.parse("$backendUrl/emergency"));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("EMERGENCY SIGNAL BROADCASTED"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint("SOS failed: $e");
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.isAccessibilityMode ? Colors.black : const Color(0xFF151921),
        title: Text(widget.userName, style: const TextStyle(fontSize: 14)),
        actions: [Icon(Icons.shield, color: isBrainOnline ? Colors.greenAccent : Colors.redAccent, size: 14), const SizedBox(width: 15)],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("USER CONDITION", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(widget.userCondition, style: TextStyle(color: widget.userCondition == "NONE" ? Colors.cyanAccent : Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                Icon(Icons.medical_services_outlined, color: widget.userCondition == "NONE" ? Colors.grey : Colors.orangeAccent),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: widget.isAccessibilityMode ? 1 : 2,
              padding: const EdgeInsets.all(15), crossAxisSpacing: 10, mainAxisSpacing: 10,
              childAspectRatio: widget.isAccessibilityMode ? 2.5 : 1.0,
              children: [
                _buildCard("LIGHTS", isLightOn ? Icons.lightbulb : Icons.lightbulb_outline, isLightOn ? "ACTIVE" : "OFF", isLightOn ? Colors.amber : Colors.blueGrey, isLightOn, () => _toggleDevice("light")),
                _buildCard("ENTRANCE", isDoorLocked ? Icons.security : Icons.lock_open, isDoorLocked ? "SECURED" : "UNLOCKED", isDoorLocked ? const Color(0xFF00E5FF) : Colors.greenAccent, !isDoorLocked, () => _toggleDevice("door")),
                _buildCard("CLIMATE", Icons.mode_fan_off_rounded, isFanOn ? "FAN ACTIVE" : "FAN OFF", isFanOn ? Colors.blueAccent : Colors.blueGrey, isFanOn, () => _toggleDevice("fan")),
                _buildCard("TEMP", Icons.thermostat, "${temperature.toStringAsFixed(1)}°C", Colors.orangeAccent, true, null),
                _buildCard("SOS", Icons.warning, "EMERGENCY", Colors.redAccent, true, () => _triggerSOS()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String label, IconData icon, String status, Color color, bool isActive, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: widget.isAccessibilityMode ? Colors.black : const Color(0xFF151921),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? color : Colors.white10, width: widget.isAccessibilityMode ? 4 : 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: widget.isAccessibilityMode ? 60 : 40, color: color),
            Text(label, style: TextStyle(fontSize: widget.isAccessibilityMode ? 20 : 12, color: Colors.grey, fontWeight: FontWeight.bold)),
            Text(status, style: TextStyle(fontSize: widget.isAccessibilityMode ? 24 : 16, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// --- PROFILES / SECURITY SCREEN ---
class SecurityScreen extends StatefulWidget {
  final Function(String, String, String, bool) onUserSwitch;
  const SecurityScreen({super.key, required this.onUserSwitch});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List _profiles = [];
  final String backendUrl = "http://10.0.2.2:8080";

  @override
  void initState() { super.initState(); _fetchProfiles(); }

  Future<void> _fetchProfiles() async {
    try {
      final response = await http.get(Uri.parse("$backendUrl/profiles"));
      if (response.statusCode == 200) setState(() => _profiles = json.decode(response.body));
    } catch (e) { debugPrint("Profiles error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("USER PROFILES")),
      body: ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: _profiles.length,
        itemBuilder: (context, index) {
          final p = _profiles[index];
          return Card(
            color: const Color(0xFF151921),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.cyanAccent)),
              title: Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${p['role']} | ${p['condition']}"),
              trailing: ElevatedButton(
                onPressed: () => widget.onUserSwitch(p['name'], p['role'], p['condition'], p['accessibility']),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF).withOpacity(0.1)),
                child: const Text("SWITCH", style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10)),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- HISTORY & SETTINGS (Simplified for brevity) ---
class HistoryScreen extends StatelessWidget { const HistoryScreen({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("HISTORY")), body: const Center(child: Text("No protocols logged."))); }
class SettingsScreen extends StatelessWidget {
  final bool isAccessibilityMode;
  final Function(bool) onAccessibilityToggle;
  const SettingsScreen({super.key, required this.isAccessibilityMode, required this.onAccessibilityToggle});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("SETTINGS")), body: SwitchListTile(title: const Text("Accessibility Mode"), value: isAccessibilityMode, onChanged: onAccessibilityToggle));
}
