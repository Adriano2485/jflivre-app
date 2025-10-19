// main.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------
/// ATENÇÃO: antes de rodar:
/// 1) Configure o Firebase (google-services.json / GoogleService-Info.plist)
/// 2) Adicione a API key do Google Maps no AndroidManifest (Android) e no Info.plist (iOS)
/// 3) Adicione as dependências no pubspec.yaml e rode flutter pub get
/// 4) Permissões de localização nas plataformas (AndroidManifest / Info.plist)
/// ---------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

enum ProfileType { driver, passenger }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideApp Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Entry screen: login / register and choose profile
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  ProfileType _profileType = ProfileType.passenger;
  bool _isLoading = false;

  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preencha nome, email e senha')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;
      final usersRef = FirebaseFirestore.instance.collection('users');
      await usersRef.doc(uid).set({
        'name': name,
        'email': email,
        'profile': _profileType == ProfileType.driver ? 'driver' : 'passenger',
        'createdAt': DateTime.now(),
      });
      // If driver, create motorista doc minimal
      if (_profileType == ProfileType.driver) {
        await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
          'uid': uid,
          'name': name,
          'pixKey': null,
          'available': false,
          'location': null,
          'updatedAt': DateTime.now(),
        });
      }
      _navigateToHome();
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: ${e.message}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass);
      // Ensure user profile exists
      final uid = cred.user!.uid;
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) {
        // fallback: create as passenger
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': _nameCtrl.text.isEmpty ? 'Usuário' : _nameCtrl.text,
          'email': email,
          'profile': 'passenger',
          'createdAt': DateTime.now(),
        });
      }
      _navigateToHome();
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: ${e.message}')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToHome() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .then((doc) {
      final profile = doc.exists ? doc['profile'] as String : 'passenger';
      if (profile == 'driver') {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => DriverHomeScreen(uid: user.uid)));
      } else {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => PassengerHomeScreen(uid: user.uid)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RideApp - Login / Cadastro'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 8),
                TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-mail')),
                const SizedBox(height: 8),
                TextField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    obscureText: true),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Perfil: '),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Passageiro'),
                      selected: _profileType == ProfileType.passenger,
                      onSelected: (_) =>
                          setState(() => _profileType = ProfileType.passenger),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Motorista'),
                      selected: _profileType == ProfileType.driver,
                      onSelected: (_) =>
                          setState(() => _profileType = ProfileType.driver),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _isLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          ElevatedButton.icon(
                              onPressed: _register,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Cadastrar')),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                              onPressed: _login,
                              icon: const Icon(Icons.login),
                              label: const Text('Entrar')),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------
/// DRIVER HOME SCREEN
/// ---------------------------
class DriverHomeScreen extends StatefulWidget {
  final String uid;
  const DriverHomeScreen({super.key, required this.uid});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _pixCtrl = TextEditingController();
  bool _available = false;
  bool _loading = true;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  late final CollectionReference driversRef;
  late final CollectionReference ridesRef;
  Map<String, dynamic>? driverData;
  StreamSubscription<QuerySnapshot>? _rideListener;
  List<Map<String, dynamic>> incomingRides = [];

  @override
  void initState() {
    super.initState();
    driversRef = FirebaseFirestore.instance.collection('drivers');
    ridesRef = FirebaseFirestore.instance.collection('rides');
    _loadDriver();
  }

  Future<void> _loadDriver() async {
    final doc = await driversRef.doc(widget.uid).get();
    if (doc.exists) {
      driverData = doc.data() as Map<String, dynamic>?;
      _pixCtrl.text = driverData?['pixKey'] ?? '';
      _available = (driverData?['available'] ?? false) as bool;
    } else {
      // create minimal
      await driversRef.doc(widget.uid).set({
        'uid': widget.uid,
        'name': 'Motorista',
        'pixKey': null,
        'available': false,
        'location': null,
        'updatedAt': DateTime.now(),
      });
    }
    setState(() => _loading = false);
    if (_available) _startLocationUpdates();
    _listenForAssignedRides();
  }

  void _listenForAssignedRides() {
    // Rides assigned to this driver with status 'requested' or 'accepted'
    _rideListener = ridesRef
        .where('driverId', isEqualTo: widget.uid)
        .snapshots()
        .listen((snap) {
      incomingRides = snap.docs.map((d) {
        final m = d.data() as Map<String, dynamic>;
        m['rideId'] = d.id;
        return m;
      }).toList();
      setState(() {});
    });
  }

  Future<void> _savePix() async {
    setState(() => _loading = true);
    await driversRef.doc(widget.uid).set({
      'uid': widget.uid,
      'pixKey': _pixCtrl.text.trim(),
      'available': _available,
      'name': driverData?['name'] ?? 'Motorista',
      'updatedAt': DateTime.now(),
    }, SetOptions(merge: true));
    setState(() => _loading = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Chave PIX salva')));
  }

  Future<void> _toggleAvailable(bool val) async {
    setState(() => _available = val);
    await driversRef.doc(widget.uid).set(
        {'available': val, 'updatedAt': DateTime.now()},
        SetOptions(merge: true));
    if (val) {
      await _startLocationUpdates();
    } else {
      await _stopLocationUpdates();
      // remove location from firestore
      await driversRef
          .doc(widget.uid)
          .set({'location': null}, SetOptions(merge: true));
    }
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ative o GPS')));
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')));
      return;
    }

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          distanceFilter: 10, accuracy: LocationAccuracy.best),
    ).listen((pos) async {
      _lastPosition = pos;
      await driversRef.doc(widget.uid).set({
        'location': {'lat': pos.latitude, 'lng': pos.longitude},
        'updatedAt': DateTime.now(),
        'available': _available,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _stopLocationUpdates() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _acceptRide(Map<String, dynamic> ride) async {
    final rideId = ride['rideId'] as String;
    await ridesRef.doc(rideId).update({
      'status': 'accepted',
      'driverAcceptedAt': DateTime.now(),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Corrida aceita')));
  }

  Future<void> _markPaid(Map<String, dynamic> ride) async {
    final rideId = ride['rideId'] as String;
    await ridesRef.doc(rideId).update({
      'status': 'paid',
      'paidAt': DateTime.now(),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Marcado como pago')));
  }

  Future<void> _completeRide(Map<String, dynamic> ride) async {
    final rideId = ride['rideId'] as String;
    await ridesRef
        .doc(rideId)
        .update({'status': 'completed', 'completedAt': DateTime.now()});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Corrida finalizada')));
  }

  Future<void> _logout() async {
    await _stopLocationUpdates();
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _rideListener?.cancel();
    super.dispose();
  }

  Widget _buildIncomingRidesTile(Map<String, dynamic> ride) {
    final status = ride['status'] as String? ?? 'requested';
    final passengerName = ride['passengerName'] ?? 'Passageiro';
    final value = (ride['value'] ?? 0).toDouble();
    return Card(
      child: ListTile(
        title:
            Text('Corrida: R\$ ${value.toStringAsFixed(2)} - $passengerName'),
        subtitle: Text('Status: $status'),
        trailing: Wrap(spacing: 8, children: [
          if (status == 'requested')
            ElevatedButton(
                onPressed: () => _acceptRide(ride),
                child: const Text('Aceitar')),
          if (status == 'accepted')
            ElevatedButton(
                onPressed: () => _markPaid(ride),
                child: const Text('Marcar pago')),
          if (status == 'paid')
            ElevatedButton(
                onPressed: () => _completeRide(ride),
                child: const Text('Finalizar')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = driverData?['name'] ?? 'Motorista';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Motorista'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('Bem-vindo, $name',
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _pixCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Sua chave PIX')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Disponível para corridas:'),
                      Switch(value: _available, onChanged: _toggleAvailable),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                      onPressed: _savePix,
                      icon: const Icon(Icons.save),
                      label: const Text('Salvar')),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text('Corridas atribuídas',
                      style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: incomingRides.isEmpty
                        ? const Center(child: Text('Nenhuma corrida atribuída'))
                        : ListView.builder(
                            itemCount: incomingRides.length,
                            itemBuilder: (_, i) =>
                                _buildIncomingRidesTile(incomingRides[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// ---------------------------
/// PASSENGER HOME SCREEN
/// ---------------------------
class PassengerHomeScreen extends StatefulWidget {
  final String uid;
  const PassengerHomeScreen({super.key, required this.uid});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  Completer<GoogleMapController> _mapCtrl = Completer();
  LatLng? _currentPos;
  bool _loading = true;
  Set<Marker> _markers = {};
  StreamSubscription<QuerySnapshot>? _driversListener;
  final driversRef = FirebaseFirestore.instance.collection('drivers');
  final ridesRef = FirebaseFirestore.instance.collection('rides');

  @override
  void initState() {
    super.initState();
    _initLocation();
    _listenAvailableDrivers();
  }

  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ative o GPS')));
      setState(() => _loading = false);
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')));
      setState(() => _loading = false);
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPos = LatLng(pos.latitude, pos.longitude);
      _loading = false;
    });
    final controller = await _mapCtrl.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(_currentPos!, 14));
  }

  void _listenAvailableDrivers() {
    _driversListener = driversRef
        .where('available', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final markers = <Marker>{};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final loc = data['location'];
        if (loc == null) continue;
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final marker = Marker(
          markerId: MarkerId(doc.id),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
              title: data['name'] ?? 'Motorista',
              snippet: 'Toque para solicitar'),
          onTap: () => _showDriverCard(doc.id, data),
        );
        markers.add(marker);
      }
      setState(() => _markers = markers);
    });
  }

  Future<void> _showDriverCard(
      String driverId, Map<String, dynamic> driverData) async {
    final name = driverData['name'] ?? 'Motorista';
    final pix = driverData['pixKey'];
    final distanceText = _calculateDistanceText(driverData['location']);
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Distância: $distanceText'),
                const SizedBox(height: 8),
                Text('PIX: ${pix ?? 'Não cadastrado'}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: pix == null
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: pix));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Chave copiada')));
                            },
                      child: const Text('Copiar PIX'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _requestRide(driverId, driverData),
                      child: const Text('Solicitar corrida'),
                    ),
                  ],
                )
              ]),
        );
      },
    );
  }

  String _calculateDistanceText(dynamic location) {
    if (_currentPos == null || location == null) return '-';
    try {
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final d = Geolocator.distanceBetween(
          _currentPos!.latitude, _currentPos!.longitude, lat, lng);
      if (d < 1000) return '${d.toStringAsFixed(0)} m';
      return '${(d / 1000).toStringAsFixed(1)} km';
    } catch (e) {
      return '-';
    }
  }

  Future<void> _requestRide(
      String driverId, Map<String, dynamic> driverData) async {
    final passengerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .get();
    final passengerName =
        passengerDoc.exists ? passengerDoc['name'] : 'Passageiro';
    final value = _estimateValue();
    final rideId = const Uuid().v4();
    await ridesRef.doc(rideId).set({
      'rideId': rideId,
      'driverId': driverId,
      'passengerId': widget.uid,
      'passengerName': passengerName,
      'value': value,
      'status': 'requested',
      'createdAt': DateTime.now(),
      'driverSnapshot': driverData,
      'pickupLocation': _currentPos == null
          ? null
          : {'lat': _currentPos!.latitude, 'lng': _currentPos!.longitude},
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Solicitação enviada')));
    // open ride status screen
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RideStatusScreen(rideId: rideId, passengerId: widget.uid)));
  }

  double _estimateValue() {
    // Simples estimativa: valor fixo + por km (demo)
    return 15.0;
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const AuthGate()), (r) => false);
  }

  @override
  void dispose() {
    _driversListener?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentPos ?? const LatLng(-23.55052, -46.633308);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passageiro - Mapa'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 14),
              myLocationEnabled: true,
              markers: _markers,
              onMapCreated: (c) => _mapCtrl.complete(c),
            ),
    );
  }
}

/// RIDE STATUS SCREEN (Passenger)
class RideStatusScreen extends StatefulWidget {
  final String rideId;
  final String passengerId;
  const RideStatusScreen(
      {super.key, required this.rideId, required this.passengerId});

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  final ridesRef = FirebaseFirestore.instance.collection('rides');
  StreamSubscription<DocumentSnapshot>? _rideSub;
  Map<String, dynamic>? _ride;
  @override
  void initState() {
    super.initState();
    _rideSub = ridesRef.doc(widget.rideId).snapshots().listen((snap) {
      if (!snap.exists) return;
      setState(() {
        _ride = snap.data() as Map<String, dynamic>?;
      });
    });
  }

  Future<void> _confirmPaid() async {
    if (_ride == null) return;
    await ridesRef
        .doc(widget.rideId)
        .update({'status': 'paid', 'paidAt': DateTime.now()});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Marcado como pago')));
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ride == null)
      return Scaffold(body: const Center(child: CircularProgressIndicator()));
    final status = _ride!['status'] as String? ?? 'requested';
    final driverSnapshot = _ride!['driverSnapshot'] as Map<String, dynamic>?;
    final pix = driverSnapshot != null ? driverSnapshot['pixKey'] : null;
    final driverName =
        driverSnapshot != null ? driverSnapshot['name'] : 'Motorista';
    final value = (_ride!['value'] ?? 0).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Status da corrida')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Status: $status', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            Text('Motorista: $driverName'),
            const SizedBox(height: 8),
            Text('Valor: R\$ ${value.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            const Divider(),
            Text('Chave PIX do motorista: ${pix ?? 'Não informada'}'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: pix == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: pix));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Chave copiada')));
                        },
                  child: const Text('Copiar PIX'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: status == 'paid' ? null : _confirmPaid,
                  child: const Text('Já realizei o pagamento'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
