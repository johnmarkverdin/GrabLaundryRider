import 'dart:io'; // 👈 for File
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // 👈 for picking images
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'package:flutter/foundation.dart'; // 👈 fixes kIsWeb
import 'package:shared_preferences/shared_preferences.dart'; // 👈 for remember me clear
import 'auth_rider_page.dart'; // 👈 to go back to login

class RiderHomePage extends StatefulWidget {
  const RiderHomePage({super.key});

  @override
  State<RiderHomePage> createState() => _RiderHomePageState();
}

class _RiderHomePageState extends State<RiderHomePage> {
  String _riderFullName = '';
  List<Map<String, dynamic>> _orders = [];
  bool _loading = false;
  RealtimeChannel? _channel;

  final ImagePicker _picker = ImagePicker(); // 👈 image picker

  // Status flow for rider
  final List<String> _statusFlow = const [
    'accepted',
    'picked_up',
    'in_delivery',
    'completed',
  ];

  @override
  void initState() {
    super.initState();
    _syncRiderProfileFromAuth(); // 🔹 ensure rider exists in profiles with role='rider'
    _loadOrders();
    _initRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ---------- SYNC RIDER PROFILE ----------
  Future<void> _syncRiderProfileFromAuth() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};

    final fullName = (meta['full_name'] ??
        meta['name'] ??
        meta['user_name'] ??
        user.email
            ?.split('@')
            .first ??
        'Rider')
        .toString()
        .trim();

    if (mounted) {
      setState(() {
        _riderFullName = fullName;
      });
    }

    try {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName,
        'role': 'rider',
      });
    } catch (e) {
      _snack('Failed to sync rider profile: $e');
    }
  }

  // ---------- LOAD ALL ORDERS ASSIGNED TO LOGGED-IN RIDER ----------
  Future<void> _loadOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _snack('Not logged in as rider');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('laundry_orders')
          .select('''
            id,
            customer_id,
            customer:profiles!laundry_orders_customer_id_fkey ( full_name ),
            pickup_address,
            delivery_address,
            status,
            service,
            payment_method,
            pickup_at,
            delivery_at,
            proof_of_billing_url,
            total_price,
            delivery_fee,
            notes
          ''')
          .eq('rider_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _orders = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      _snack('Failed to load orders: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- REALTIME ----------
  void _initRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _channel?.unsubscribe();

    _channel = supabase
        .channel('rider_orders_${user.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'laundry_orders',
      callback: (_) => _loadOrders(),
    )
        .subscribe();
  }

  // ---------- STATUS FLOW ----------
  String? _nextStatus(String current) {
    final idx = _statusFlow.indexOf(current);
    if (idx == -1 || idx == _statusFlow.length - 1) return null;
    return _statusFlow[idx + 1];
  }

  Future<void> _advanceStatus(Map<String, dynamic> order) async {
    final current = (order['status'] ?? '').toString();
    final next = _nextStatus(current);
    if (next == null) {
      _snack('Order is already on the final status.');
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase
          .from('laundry_orders')
          .update({'status': next})
          .eq('id', order['id']);

      await _loadOrders();
    } catch (e) {
      _snack('Failed to update order status: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- PROOF OF BILLING UPLOAD ----------
  Future<void> _pickAndUploadProof(Map<String, dynamic> order) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _snack('Not logged in');
      return;
    }

    // 🚫 Block unsupported platforms (Windows/Linux/macOS)
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _snack('Image upload is only supported on Android and iOS devices.');
      return;
    }

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (picked == null) return;

      setState(() => _loading = true);

      final file = File(picked.path);
      final fileName =
          'order_${order['id']}_${DateTime
          .now()
          .millisecondsSinceEpoch}.jpg';

      final storage = supabase.storage.from('proof-of-billing');
      await storage.upload(fileName, file);

      final publicUrl = storage.getPublicUrl(fileName);

      await supabase
          .from('laundry_orders')
          .update({'proof_of_billing_url': publicUrl})
          .eq('id', order['id']);

      _snack('Proof of billing uploaded successfully.');
      await _loadOrders();
    } catch (e) {
      _snack('Failed to upload proof: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showProofDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) =>
          Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
    );
  }

  // ---------- HELPERS ----------
  String _fmt(dynamic v) {
    if (v == null) return '-';
    try {
      final dt = DateTime.parse(v.toString());
      return '${dt.month}/${dt.day} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(
          2, '0')}';
    } catch (_) {
      return v.toString();
    }
  }

  Future<void> _logout() async {
    try {
      // Clear remember-me for rider
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('rider_remember_me');
      await prefs.remove('rider_email');

      // Sign out from Supabase
      await supabase.auth.signOut();

      if (!mounted) return;

      // Go back to RiderAuthPage and clear navigation stack
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RiderAuthPage()),
            (route) => false,
      );
    } catch (e) {
      _snack('Error signing out: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF4F46E5); // indigo
      case 'picked_up':
        return const Color(0xFF6366F1); // soft indigo
      case 'in_delivery':
        return const Color(0xFFF97316); // amber/orange
      case 'completed':
        return const Color(0xFF16A34A); // green
      default:
        return Colors.grey;
    }
  }

  String _prettyStatus(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'picked_up':
        return 'Picked Up';
      case 'Arrived at shop':
        return 'Arrived at Shop';
      case 'in_delivery':
        return 'In Delivery';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final loader = _loading
        ? const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
    )
        : const SizedBox.shrink();

    final secondaryTextColor = Colors.grey.shade600;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        elevation: 0.5,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF111827),
                Color(0xFF1F2937),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Rider Dashboard',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Monitor assigned pickups and deliveries.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Orders',
            onPressed: _loadOrders,
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sign Out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: loader,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top summary card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4F46E5),
                    Color(0xFF0EA5E9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Today\'s Overview',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _orders.isEmpty
                              ? 'You do not have any assigned orders at the moment.'
                              : 'You currently have ${_orders
                              .length} active order(s) assigned.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Orders list
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadOrders,
                child: _orders.isEmpty
                    ? ListView(
                  children: [
                    const SizedBox(height: 80),
                    Icon(
                      Icons.inbox_outlined,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'No assigned orders',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Orders assigned to you will be displayed here.\nPlease keep the application open to receive new tasks.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                )
                    : ListView.builder(
                  padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _orders.length,
                  itemBuilder: (context, i) {
                    final o = _orders[i];

                    final customer =
                    o['customer'] as Map<String, dynamic>?;
                    final customerName = (customer?['full_name'] ??
                        o['customer_name'] ??
                        o['customer_id'] ??
                        'Customer')
                        .toString()
                        .trim();

                    final next =
                    _nextStatus((o['status'] ?? '').toString());
                    final proofUrl =
                    o['proof_of_billing_url'] as String?;
                    final status =
                    (o['status'] ?? '').toString();
                    final statusColor = _statusColor(status);
                    final totalPrice = o['total_price'];
                    final notes =
                        o['notes']?.toString().trim() ?? '';

                    return Padding(
                      padding:
                      const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                            BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(0.04),
                                blurRadius: 8,
                                offset:
                                const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Colored top strip
                              Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient:
                                  LinearGradient(
                                    colors: [
                                      statusColor,
                                      statusColor
                                          .withOpacity(
                                          0.75),
                                    ],
                                    begin:
                                    Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                const EdgeInsets.all(
                                    16),
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        Container(
                                          padding:
                                          const EdgeInsets
                                              .all(10),
                                          decoration:
                                          BoxDecoration(
                                            color: statusColor
                                                .withOpacity(
                                                0.12),
                                            shape: BoxShape
                                                .circle,
                                          ),
                                          child: Icon(
                                            Icons
                                                .local_laundry_service,
                                            size: 22,
                                            color:
                                            statusColor,
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child:
                                                    Text(
                                                      customerName.isEmpty
                                                          ? 'Customer'
                                                          : customerName,
                                                      style:
                                                      const TextStyle(
                                                        fontSize:
                                                        16,
                                                        fontWeight:
                                                        FontWeight.w700,
                                                      ),
                                                      overflow:
                                                      TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      width:
                                                      8),
                                                  Container(
                                                    padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                      horizontal:
                                                      10,
                                                      vertical:
                                                      4,
                                                    ),
                                                    decoration:
                                                    BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(
                                                          0.12),
                                                      borderRadius:
                                                      BorderRadius.circular(20),
                                                    ),
                                                    child:
                                                    Text(
                                                      _prettyStatus(status),
                                                      style:
                                                      TextStyle(
                                                        fontSize:
                                                        11,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                        color:
                                                        statusColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(
                                                  height:
                                                  4),
                                              Text(
                                                _riderFullName
                                                    .isEmpty
                                                    ? 'Rider'
                                                    : _riderFullName,
                                                style:
                                                TextStyle(
                                                  fontSize:
                                                  12,
                                                  color:
                                                  secondaryTextColor,
                                                ),
                                              ),
                                              const SizedBox(
                                                  height:
                                                  2),
                                              Text(
                                                o['service'] !=
                                                    null
                                                    ? o['service']
                                                    .toString()
                                                    : 'Laundry service',
                                                style:
                                                TextStyle(
                                                  fontSize:
                                                  12,
                                                  color:
                                                  secondaryTextColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: 14),
                                    // Pickup & Delivery
                                    Row(
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        Column(
                                          children: [
                                            Icon(
                                              Icons
                                                  .radio_button_checked,
                                              size: 16,
                                              color: Colors
                                                  .green
                                                  .shade500,
                                            ),
                                            Container(
                                              width: 2,
                                              height: 30,
                                              color: Colors
                                                  .grey
                                                  .shade300,
                                            ),
                                            Icon(
                                              Icons
                                                  .location_on,
                                              size: 18,
                                              color: Colors
                                                  .red
                                                  .shade400,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(
                                            width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                            children: [
                                              Text(
                                                'Pickup Address',
                                                style:
                                                TextStyle(
                                                  fontSize:
                                                  11,
                                                  color:
                                                  secondaryTextColor,
                                                ),
                                              ),
                                              Text(
                                                o['pickup_address'] ??
                                                    'Not specified',
                                                style:
                                                const TextStyle(
                                                  fontSize:
                                                  13,
                                                  fontWeight:
                                                  FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(
                                                  height:
                                                  8),
                                              Text(
                                                'Delivery Address',
                                                style:
                                                TextStyle(
                                                  fontSize:
                                                  11,
                                                  color:
                                                  secondaryTextColor,
                                                ),
                                              ),
                                              Text(
                                                o['delivery_address'] ??
                                                    'Not specified',
                                                style:
                                                const TextStyle(
                                                  fontSize:
                                                  13,
                                                  fontWeight:
                                                  FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    if (notes.isNotEmpty) ...[
                                      const SizedBox(
                                          height: 8),
                                      Text(
                                        'Notes',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                          secondaryTextColor,
                                        ),
                                      ),
                                      Text(
                                        notes,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontStyle:
                                          FontStyle.italic,
                                          color:
                                          secondaryTextColor,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(
                                        height: 12),
                                    // Time & payment row
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.schedule,
                                                size: 16,
                                                color: Colors
                                                    .grey,
                                              ),
                                              const SizedBox(
                                                  width:
                                                  6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Pickup: ${_fmt(
                                                          o['pickup_at'])}',
                                                      style:
                                                      TextStyle(
                                                        fontSize:
                                                        11,
                                                        color:
                                                        secondaryTextColor,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Delivery: ${_fmt(
                                                          o['delivery_at'])}',
                                                      style:
                                                      TextStyle(
                                                        fontSize:
                                                        11,
                                                        color:
                                                        secondaryTextColor,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Total: ₱${(totalPrice ??
                                                          0).toString()}',
                                                      style:
                                                      TextStyle(
                                                        fontSize:
                                                        12,
                                                        fontWeight:
                                                        FontWeight.w600,
                                                        color:
                                                        secondaryTextColor,
                                                      ),
                                                    ),
                                                    Text(
                                                      'delivery: ₱${(o['delivery_fee'] ??
                                                          0).toString()}',
                                                      style:
                                                      TextStyle(
                                                        fontSize:
                                                        11,
                                                        fontWeight:
                                                        FontWeight.w500,
                                                        color:
                                                        secondaryTextColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (o['payment_method'] !=
                                            null)
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                              horizontal:
                                              10,
                                              vertical:
                                              6,
                                            ),
                                            decoration:
                                            BoxDecoration(
                                              color: Colors
                                                  .indigo
                                                  .shade50,
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                  16),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .payments_rounded,
                                                  size:
                                                  16,
                                                  color: Colors
                                                      .indigo,
                                                ),
                                                const SizedBox(
                                                    width:
                                                    6),
                                                Text(
                                                  o['payment_method']
                                                      .toString()
                                                      .toUpperCase(),
                                                  style:
                                                  const TextStyle(
                                                    fontSize:
                                                    11,
                                                    fontWeight:
                                                    FontWeight.w600,
                                                    color: Colors
                                                        .indigo,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: 14),
                                    // Buttons
                                    Row(
                                      children: [
                                        Expanded(
                                          child:
                                          ElevatedButton.icon(
                                            onPressed: _loading
                                                ? null
                                                : () =>
                                                _pickAndUploadProof(
                                                    o),
                                            icon: const Icon(
                                              Icons
                                                  .upload_file_rounded,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'Upload Proof',
                                              style: TextStyle(
                                                  fontSize:
                                                  13),
                                            ),
                                            style: ElevatedButton
                                                .styleFrom(
                                              backgroundColor:
                                              Colors.white,
                                              foregroundColor:
                                              Colors
                                                  .indigo,
                                              elevation:
                                              0,
                                              side:
                                              BorderSide(
                                                color: Colors
                                                    .indigo
                                                    .shade100,
                                              ),
                                              shape:
                                              RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                    14),
                                              ),
                                              padding:
                                              const EdgeInsets
                                                  .symmetric(
                                                vertical:
                                                10,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                            width: 8),
                                        if (proofUrl != null &&
                                            proofUrl
                                                .trim()
                                                .isNotEmpty)
                                          ElevatedButton.icon(
                                            onPressed: () =>
                                                _showProofDialog(
                                                    proofUrl),
                                            icon: const Icon(
                                              Icons
                                                  .image_rounded,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'View Proof',
                                              style: TextStyle(
                                                  fontSize:
                                                  13),
                                            ),
                                            style: ElevatedButton
                                                .styleFrom(
                                              backgroundColor:
                                              Colors
                                                  .green
                                                  .shade50,
                                              foregroundColor:
                                              Colors
                                                  .green
                                                  .shade700,
                                              elevation:
                                              0,
                                              shape:
                                              RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius
                                                    .circular(
                                                    14),
                                              ),
                                              padding:
                                              const EdgeInsets
                                                  .symmetric(
                                                vertical:
                                                10,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: 10),
                                    if (next != null)
                                      SizedBox(
                                        width:
                                        double.infinity,
                                        child:
                                        ElevatedButton(
                                          onPressed: _loading
                                              ? null
                                              : () =>
                                              _advanceStatus(
                                                  o),
                                          style: ElevatedButton
                                              .styleFrom(
                                            backgroundColor:
                                            statusColor,
                                            foregroundColor:
                                            Colors.white,
                                            shape:
                                            RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                  16),
                                            ),
                                            padding:
                                            const EdgeInsets
                                                .symmetric(
                                              vertical:
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Mark as ${_prettyStatus(next)}',
                                            style:
                                            const TextStyle(
                                              fontSize:
                                              14,
                                              fontWeight:
                                              FontWeight
                                                  .w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}