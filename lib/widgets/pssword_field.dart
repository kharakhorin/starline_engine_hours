import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  // ignore: use_key_in_widget_constructors
  const PasswordField(
      {this.fieldKey,
      this.hintText,
      this.labelText,
      this.controller,
      this.onChanged});

  final Key? fieldKey;
  final String? hintText;
  final String? labelText;
  final TextEditingController? controller;
  final void Function(String)? onChanged;

  @override
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      obscureText: _obscureText,
      controller: widget.controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.hintText,
        labelText: widget.labelText,
        suffixIcon: GestureDetector(
          onTap: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
          child: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}
