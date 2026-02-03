import 'package:flutter/material.dart';
import '../views/account_detail_view.dart';
import '../views/user_management_view.dart';
import '../views/login_history_view.dart';
import '../views/reports_view.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.settings, size: 24, color: Colors.black),
                  ],
                ),
              ),

              // Security notice
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(4),
                decoration: ShapeDecoration(
                  color: const Color(0x19FF3B30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.security, color: const Color(0xFFFF3B30), size: 18),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'All profile running in this app is secure. The new',
                        style: TextStyle(
                          color: const Color(0xFFFF3B30),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Balance card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(10),
                decoration: ShapeDecoration(
                  color: const Color(0xFF22547C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Credit: 50,000',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      'Balance: 25,251.50',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Menu items
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    _buildMenuItem(context, Icons.admin_panel_settings, 'Admin Setting'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.account_circle, 'Account Detail'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.people, 'User Management'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.assessment, 'Reports'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.settings, 'Settings'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.person_add, 'Invite Friends'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.history, 'Login History'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.logout, 'Logout', isRed: true),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Delete account
              Text(
                'Delete Account',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, {bool isRed = false}) {
    return GestureDetector(
      onTap: () {
        if (title == 'Account Detail') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AccountDetailView()),
          );
        } else if (title == 'User Management') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UserManagementView()),
          );
        } else if (title == 'Login History') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LoginHistoryView()),
          );
        } else if (title == 'Reports') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReportsView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isRed ? const Color(0xFFFF3B30) : Colors.black,
                ),
                SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: isRed ? const Color(0xFFFF3B30) : Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: const Color(0xFFC7C7CC), indent: 16, endIndent: 16);
  }
}
