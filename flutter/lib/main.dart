import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/homepage.dart';
import 'pages/connection_page.dart';

void main() {
 runApp(MaterialApp(
    theme: ThemeData.dark(),
    home: HomePage(device: null),
  ));
}