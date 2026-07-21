import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/theme_provider.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/student_payments/student_payments_bloc.dart';
import '../bloc/student_payments/student_payments_event.dart';
import '../bloc/student_payments/student_payments_state.dart';
import '../../../../services/api_service.dart';

class StudentPaymentsScreen extends StatefulWidget {
  final bool isInline;
  const StudentPaymentsScreen({super.key, this.isInline = false});

  @override
  State<StudentPaymentsScreen> createState() => _StudentPaymentsScreenState();
}

class _StudentPaymentsScreenState extends State<StudentPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<StudentPaymentsBloc>().add(FetchStudentPayments());
  }

  Future<void> _payNow(String paymentId) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
      );
      
      final response = await ApiService.post('/payments/$paymentId/pay', {});
      
      Navigator.of(context).pop(); // dismiss loading
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment Successful!'), backgroundColor: Colors.green),
        );
        context.read<StudentPaymentsBloc>().add(FetchStudentPayments());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment Failed. Please try again.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: widget.isInline
          ? null
          : AppBar(
              title: Text('My Payments', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, letterSpacing: 1)),
              backgroundColor: Colors.transparent,
              flexibleSpace: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: context.isDark ? const Color(0xFF0F172A).withOpacity(0.6) : Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
              iconTheme: IconThemeData(color: context.textColor),
              elevation: 0,
            ),
      body: Stack(
        children: [
          if (!widget.isInline)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.isDark ? [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)] : [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          SafeArea(
            child: BlocBuilder<StudentPaymentsBloc, StudentPaymentsState>(
              builder: (context, state) {
                if (state is StudentPaymentsLoading || state is StudentPaymentsInitial) {
                  return Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
                } else if (state is StudentPaymentsError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                        SizedBox(height: 16),
                        Text(state.message, style: TextStyle(color: context.textColor70)),
                        SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                          onPressed: () => context.read<StudentPaymentsBloc>().add(FetchStudentPayments()),
                          child: const Text('Retry', style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  );
                } else if (state is StudentPaymentsLoaded) {
                  final payments = state.payments;
                  final pendingPayments = payments.where((p) => p['status'] == 'PENDING').toList();
                  final paidPayments = payments.where((p) => p['status'] == 'PAID').toList();

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status Card
                        if (pendingPayments.isEmpty)
                          _buildUpToDateCard()
                        else
                          ...pendingPayments.map((p) => _buildDuePaymentCard(p)),
                          
                        SizedBox(height: 32),
                        Text(
                          'Payment History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textColor,
                          ),
                        ).animate().fade(duration: 400.ms, delay: 200.ms).slideX(begin: -0.1, end: 0),
                        SizedBox(height: 16),
                        
                        if (paidPayments.isEmpty)
                          Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Column(
                                children: [
                                  Icon(Icons.history_rounded, size: 64, color: Colors.white24),
                                  SizedBox(height: 16),
                                  Text(
                                    'No payment history found.',
                                    style: TextStyle(color: context.textColor54, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ).animate().fade(duration: 600.ms)
                        else
                          ...paidPayments.asMap().entries.map((entry) => _buildHistoryCard(entry.value, entry.key)),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpToDateCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF10B981).withOpacity(0.05) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? const Color(0xFF10B981).withOpacity(0.3) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF10B981).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 36),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Good!',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Your payments are up to date.',
                        style: TextStyle(color: context.textColor70, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildDuePaymentCard(Map<String, dynamic> payment) {
    final dueDate = DateTime.parse(payment['dueDate']);
    final isOverdue = DateTime.now().isAfter(dueDate);
    
    final borderColor = isOverdue ? Colors.redAccent : const Color(0xFFF59E0B);
    final bgColor = isOverdue ? Colors.redAccent.withOpacity(0.05) : const Color(0xFFF59E0B).withOpacity(0.05);
    final shadowColor = isOverdue ? Colors.redAccent.withOpacity(0.15) : const Color(0xFFF59E0B).withOpacity(0.15);

    return Container(
      margin: EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: context.isDark ? bgColor : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? borderColor.withOpacity(0.4) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : shadowColor.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: borderColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isOverdue ? Icons.warning_rounded : Icons.pending_actions_rounded,
                            color: borderColor,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          isOverdue ? 'Payment Overdue' : 'Payment Due',
                          style: TextStyle(
                            color: borderColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '\$${payment['amountDue']}',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  'Batch: ${payment['batch'] != null ? payment['batch']['name'] : 'Unknown'}',
                  style: TextStyle(color: context.textColor, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Month: ${payment['monthYear']}',
                  style: TextStyle(color: context.textColor70, fontSize: 15),
                ),
                SizedBox(height: 6),
                Text(
                  'Sessions: ${payment['sessionsCount']} @ \$${payment['feePerSession']}/session',
                  style: TextStyle(color: context.textColor54, fontSize: 14),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Due by', style: TextStyle(color: context.textColor54, fontSize: 12)),
                        SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, yyyy').format(dueDate),
                          style: TextStyle(
                            color: isOverdue ? Colors.redAccent : context.textColor,
                            fontWeight: isOverdue ? FontWeight.bold : FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        elevation: 8,
                        shadowColor: const Color(0xFF6366F1).withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _payNow(payment['_id']),
                      icon: const Icon(Icons.payment_rounded, color: Colors.white, size: 20),
                      label: const Text('Pay Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ).animate(onPlay: (c) => isOverdue ? c.repeat(reverse: true) : null).shimmer(duration: 2000.ms),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildHistoryCard(Map<String, dynamic> payment, int index) {
    final paidDate = payment['paidAt'] != null ? DateTime.parse(payment['paidAt']) : null;
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981)),
            ),
            title: Text(
              payment['batch'] != null ? payment['batch']['name'] : 'Unknown Batch',
              style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 6),
                Text('Month: ${payment['monthYear']}', style: TextStyle(color: context.textColor70)),
                if (paidDate != null)
                  Text(
                    'Paid on ${DateFormat('MMM dd, yyyy').format(paidDate)}',
                    style: TextStyle(color: context.textColor54, fontSize: 12),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${payment['amountDue']}',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                    SizedBox(width: 4),
                    Text('Paid', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 400.ms, delay: (index * 100).ms).slideY(begin: 0.1, end: 0);
  }
}
