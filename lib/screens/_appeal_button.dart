import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppealButton extends StatefulWidget {
  final String roomName;
  const AppealButton({Key? key, required this.roomName}) : super(key: key);

  @override
  State<AppealButton> createState() => _AppealButtonState();
}

class _AppealButtonState extends State<AppealButton> {
  bool _loading = false;
  bool _appealExists = false;
  bool _error = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkAppealStatus();
  }

  Future<void> _checkAppealStatus() async {
    setState(() {
      _loading = true;
      _error = false;
      _errorMsg = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = true;
          _errorMsg = 'You must be signed in to appeal.';
          _loading = false;
        });
        return;
      }
      final roomQuery = await FirebaseFirestore.instance
          .collection('rooms')
          .where('name', isEqualTo: widget.roomName)
          .limit(1)
          .get();
      if (roomQuery.docs.isEmpty) {
        setState(() {
          _error = true;
          _errorMsg = 'Room not found.';
          _loading = false;
        });
        return;
      }
      final roomDoc = roomQuery.docs.first;
      final appealsQuery = await roomDoc.reference
          .collection('appeals')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      setState(() {
        _appealExists = appealsQuery.docs.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = true;
        _errorMsg = 'Error checking appeal status: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sendAppeal() async {
    setState(() {
      _loading = true;
      _error = false;
      _errorMsg = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = true;
          _errorMsg = 'You must be signed in to appeal.';
          _loading = false;
        });
        return;
      }
      final roomQuery = await FirebaseFirestore.instance
          .collection('rooms')
          .where('name', isEqualTo: widget.roomName)
          .limit(1)
          .get();
      if (roomQuery.docs.isEmpty) {
        setState(() {
          _error = true;
          _errorMsg = 'Room not found.';
          _loading = false;
        });
        return;
      }
      final roomDoc = roomQuery.docs.first;
      await roomDoc.reference.collection('appeals').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Blocked by spam detection',
      });
      setState(() {
        _appealExists = true;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appeal sent to room admin.')),
        );
      }
    } catch (e) {
      setState(() {
        _error = true;
        _errorMsg = 'Failed to send appeal: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const OutlinedButton(
        onPressed: null,
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error) {
      return OutlinedButton(
        onPressed: _checkAppealStatus,
        child: Text(_errorMsg ?? 'Error'),
      );
    }
    if (_appealExists) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Appeal already sent', style: TextStyle(fontSize: 16)),
      );
    }
    return OutlinedButton(
      onPressed: _sendAppeal,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: const Text('Appeal Block', style: TextStyle(fontSize: 16)),
    );
  }
}
