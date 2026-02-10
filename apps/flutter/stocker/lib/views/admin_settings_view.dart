import 'package:flutter/material.dart';
import 'master_management_view.dart';
import 'user_status_view.dart';
import 'send_message_view.dart';
import 'manage_reports_view.dart';

class AdminSettingsView extends StatelessWidget {
  const AdminSettingsView({super.key});

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
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.black),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Admin Setting',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
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
                    _buildMenuItem(context, 'Master Management'),
                    _buildDivider(),
                    _buildMenuItem(context, 'User Status'),
                    _buildDivider(),
                    _buildMenuItem(context, 'Send Message'),
                    _buildDivider(),
                    _buildMenuItem(context, 'Manage Trade'),
                    _buildDivider(),
                    _buildMenuItem(context, 'Manage Reports'),
                    _buildDivider(),
                    _buildMenuItem(context, 'Set Margin'),
                    _buildDivider(),
                    _buildMenuItem(context, 'Bill Management'),
                  ],
                ),
              ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title) {
    return GestureDetector(
      onTap: () {
        if (title == 'Master Management') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MasterManagementView()),
          );
        } else if (title == 'User Status') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UserStatusView()),
          );
        } else if (title == 'Send Message') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SendMessageView()),
          );
        } else if (title == 'Manage Reports') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ManageReportsView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
            Icon(Icons.chevron_right, size: 24, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: const Color(0xFFC7C7CC), indent: 16, endIndent: 16);
  }
}
