import 'package:flutter/material.dart';

class TermsView extends StatelessWidget {
  const TermsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
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
                    'Terms',
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Duis sed odio in augue ornare hendrerit. Sed vitae euismod ex. Nam sit amet vehicula odio. Sed sed quam neque. Aenean consequat odio dolor. Proin feugiat quis tellus porta tincidunt. Sed sagittis, nisi vitae facilisis ultrices, urna nibh tristique magna, vel ultricies eros massa aliquet leo. Phasellus metus purus, posuere ac nulla nec, suscipit facilisis lorem. Vivamus sed nibh eu purus finibus consequat. Phasellus eget maximus sem. Vivamus ligula ligula, tristique at odio et, finibus ullamcorper elit. Fusce turpis enim, tempus ut mauris non, feugiat malesuada nulla. Phasellus egestas sapien ut est rutrum placerat.\n\nAliquam fermentum aliquam erat eget aliquam. Morbi vel risus eros. Nullam id gravida nulla. Fusce hendrerit molestie justo eu dictum. Maecenas elit leo, vulputate tempor ipsum eget, molestie finibus purus. Duis ac turpis porta libero cursus ultricies. Quisque fringilla ac nibh nec blandit. Donec fringilla lectus nec orci egestas molestie. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Proin egestas commodo nunc, viverra ornare nunc laoreet nec. Nunc sed nisi placerat, faucibus mi eget, ornare tellus. Praesent ante nisi, scelerisque id mattis at, porta vitae sem. In egestas tincidunt nisi porta tempor. Curabitur sed metus consectetur, consequat leo id, mattis nisi. Sed nulla sapien, auctor vitae dictum eu, tristique sit amet ex.\n\nSuspendisse fermentum rhoncus arcu, at finibus mi viverra in. Morbi id turpis a neque lacinia auctor. Vivamus ultrices malesuada metus sit amet vulputate. Suspendisse',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      height: 1.43,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
