import 'package:flutter/foundation.dart';

class UserModel with ChangeNotifier {
  int _id;
  String _email;
  String _name;

  UserModel({
    required int id,
    required String email,
    required String name,
  })  : _id = id,
        _email = email,
        _name = name;

  int get id => _id;
  String get email => _email;
  String get name => _name;

  void setUser({
    required int id,
    required String email,
    required String name,
  }) {
    _id = id;
    _email = email;
    _name = name;
    notifyListeners();
  }

  void clearUser() {
    _id = 0;
    _email = '';
    _name = '';
    notifyListeners();
  }
}