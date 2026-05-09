import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Servicio que centraliza la lógica de bloqueo de usuarios.
///
/// Estructura en Firestore:
///   bloqueos/{blockerId}_{blockedId}
///     - from: blockerId
///     - to:   blockedId
///     - timestamp: serverTimestamp
///
/// Al bloquear se borra:
///   - matches/{matchId}             (matchId = IDs ordenados unidos por _)
///   - mensajes/{matchId}/chats/*    (todos los mensajes)
///   - mensajes/{matchId}            (documento padre)
///   - likes/{a}_{b}  y  likes/{b}_{a}  (para que no se reactive un match)
class BlockService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _blockDocId(String blockerId, String blockedId) =>
      '${blockerId}_$blockedId';

  static String matchIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// Bloquea al usuario [blockedId] desde [blockerId]. Devuelve true si OK.
  static Future<bool> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    if (blockerId.isEmpty || blockedId.isEmpty || blockerId == blockedId) {
      return false;
    }
    try {
      // 1. Crear documento de bloqueo
      await _db
          .collection('bloqueos')
          .doc(_blockDocId(blockerId, blockedId))
          .set({
        'from': blockerId,
        'to': blockedId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final matchId = matchIdFor(blockerId, blockedId);

      // 2. Borrar (en paralelo) chat, match y likes
      await Future.wait([
        _deleteChatMessages(matchId),
        _deleteMatch(matchId),
        _deleteLikes(blockerId, blockedId),
      ]);

      return true;
    } catch (e) {
      debugPrint('BlockService.blockUser error: $e');
      return false;
    }
  }

  /// Desbloquea: elimina el documento de bloqueo.
  static Future<bool> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      await _db
          .collection('bloqueos')
          .doc(_blockDocId(blockerId, blockedId))
          .delete();
      return true;
    } catch (e) {
      debugPrint('BlockService.unblockUser error: $e');
      return false;
    }
  }

  /// ¿[blockerId] tiene bloqueado a [blockedId]?
  static Future<bool> isBlocked({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      final doc = await _db
          .collection('bloqueos')
          .doc(_blockDocId(blockerId, blockedId))
          .get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// IDs de usuarios que [userId] ha bloqueado.
  static Future<Set<String>> getUsersIBlocked(String userId) async {
    if (userId.isEmpty) return <String>{};
    try {
      final snap = await _db
          .collection('bloqueos')
          .where('from', isEqualTo: userId)
          .get();
      return snap.docs.map((d) => d.data()['to'] as String).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// IDs de usuarios que han bloqueado a [userId].
  static Future<Set<String>> getUsersWhoBlockedMe(String userId) async {
    if (userId.isEmpty) return <String>{};
    try {
      final snap = await _db
          .collection('bloqueos')
          .where('to', isEqualTo: userId)
          .get();
      return snap.docs.map((d) => d.data()['from'] as String).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Unión: bloqueados POR [userId] + los que han bloqueado A [userId].
  /// Para filtrar todas las relaciones en una sola llamada (discovery).
  static Future<Set<String>> getAllBlockedRelations(String userId) async {
    if (userId.isEmpty) return <String>{};
    final results = await Future.wait([
      getUsersIBlocked(userId),
      getUsersWhoBlockedMe(userId),
    ]);
    return {...results[0], ...results[1]};
  }

  // ── Privados ──────────────────────────────────────────────────────────

  static Future<void> _deleteChatMessages(String matchId) async {
    try {
      final chatsRef =
          _db.collection('mensajes').doc(matchId).collection('chats');
      while (true) {
        final snap = await chatsRef.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (snap.docs.length < 400) break;
      }
      await _db.collection('mensajes').doc(matchId).delete();
    } catch (e) {
      debugPrint('BlockService._deleteChatMessages error: $e');
    }
  }

  static Future<void> _deleteMatch(String matchId) async {
    try {
      await _db.collection('matches').doc(matchId).delete();
    } catch (e) {
      debugPrint('BlockService._deleteMatch error: $e');
    }
  }

  static Future<void> _deleteLikes(String userA, String userB) async {
    try {
      await Future.wait([
        _db.collection('likes').doc('${userA}_$userB').delete(),
        _db.collection('likes').doc('${userB}_$userA').delete(),
      ]);
    } catch (e) {
      debugPrint('BlockService._deleteLikes error: $e');
    }
  }
}