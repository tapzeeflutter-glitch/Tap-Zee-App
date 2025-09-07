import 'dart:async';
import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapzee/models/message.dart';
import 'package:tapzee/services/realtime_chat_service.dart';
import 'package:tapzee/services/hive_service.dart';

class ChatOptimizationService {
  // Message cache with LRU eviction
  static final Map<String, LinkedHashMap<String, Message>> _messageCache = {};
  static final Map<String, StreamController<List<Message>>> _streamControllers =
      {};
  static final Map<String, Timer> _debounceTimers = {};
  static final Map<String, int> _lastFetchTimes = {};

  // Configuration
  static const int maxCacheSize = 200;
  static const int messageBatchSize = 50;
  static const int debounceDelayMs =
      100; // Reduced from 300ms to 100ms for faster updates
  static const int cacheExpiryMs = 300000; // 5 minutes

  /// Get optimized message stream with caching and debouncing
  static Stream<List<Message>> getOptimizedMessagesStream(String roomId) {
    // Return existing stream if available
    if (_streamControllers.containsKey(roomId)) {
      return _streamControllers[roomId]!.stream;
    }

    // Create new stream controller
    final controller = StreamController<List<Message>>.broadcast();
    _streamControllers[roomId] = controller;

    // Load cached messages immediately
    _loadCachedMessages(roomId, controller);

    // Set up real-time listener with optimization
    _setupOptimizedListener(roomId, controller);

    // Cleanup when stream is cancelled
    controller.onCancel = () {
      _cleanupRoom(roomId);
    };

    return controller.stream;
  }

  /// Load cached messages from local storage and memory
  static Future<void> _loadCachedMessages(
    String roomId,
    StreamController<List<Message>> controller,
  ) async {
    try {
      // First, try memory cache
      if (_messageCache.containsKey(roomId) &&
          _messageCache[roomId]!.isNotEmpty) {
        final messages = _messageCache[roomId]!.values.toList();
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        controller.add(messages);
        return;
      }

      // Then, try Hive cache
      final hiveMessages = HiveService.getMessagesForRoom(roomId);
      if (hiveMessages.isNotEmpty) {
        _updateMemoryCache(roomId, hiveMessages);
        hiveMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        controller.add(hiveMessages);
      }
    } catch (e) {
      print('Error loading cached messages: $e');
    }
  }

  /// Set up optimized real-time listener with debouncing
  static void _setupOptimizedListener(
    String roomId,
    StreamController<List<Message>> controller,
  ) {
    RealtimeChatService.getMessagesStream(
      roomId,
      limit: messageBatchSize,
    ).listen(
      (messages) {
        // Cancel previous debounce timer
        _debounceTimers[roomId]?.cancel();

        // Debounce rapid updates
        _debounceTimers[roomId] = Timer(
          Duration(milliseconds: debounceDelayMs),
          () {
            _processNewMessages(roomId, messages, controller);
          },
        );
      },
      onError: (error) {
        print('Error in real-time listener: $error');
        controller.addError(error);
      },
    );
  }

  /// Process new messages with smart caching
  static void _processNewMessages(
    String roomId,
    List<Message> newMessages,
    StreamController<List<Message>> controller,
  ) {
    try {
      // Remove any optimistic messages before updating cache
      if (_messageCache.containsKey(roomId)) {
        _messageCache[roomId]!.removeWhere(
          (key, msg) => msg.id?.startsWith('temp_') ?? false,
        );
      }

      // Update memory cache
      _updateMemoryCache(roomId, newMessages);

      // Get optimized message list
      final optimizedMessages = _getOptimizedMessageList(roomId);

      // Update stream
      controller.add(optimizedMessages);

      // Update last fetch time
      _lastFetchTimes[roomId] = DateTime.now().millisecondsSinceEpoch;

      // Save to Hive in background
      _saveToHiveBackground(newMessages);
    } catch (e) {
      print('Error processing new messages: $e');
    }
  }

  /// Update memory cache with LRU eviction
  static void _updateMemoryCache(String roomId, List<Message> messages) {
    if (!_messageCache.containsKey(roomId)) {
      _messageCache[roomId] = LinkedHashMap<String, Message>();
    }

    final cache = _messageCache[roomId]!;

    for (final message in messages) {
      final messageId =
          message.id ?? message.timestamp.millisecondsSinceEpoch.toString();

      // Remove if already exists (to maintain order)
      cache.remove(messageId);

      // Add to end (most recent)
      cache[messageId] = message;
    }

    // Implement LRU eviction
    while (cache.length > maxCacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  /// Get optimized message list from cache
  static List<Message> _getOptimizedMessageList(String roomId) {
    if (!_messageCache.containsKey(roomId)) {
      return [];
    }

    final messages = _messageCache[roomId]!.values.toList();
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Return only recent messages for performance
    return messages.take(messageBatchSize).toList();
  }

  /// Save messages to Hive in background
  static void _saveToHiveBackground(List<Message> messages) {
    Timer.run(() async {
      try {
        for (final message in messages) {
          await HiveService.saveMessage(message);
        }
      } catch (e) {
        print('Error saving to Hive: $e');
      }
    });
  }

  /// Send message with optimization
  static Future<void> sendOptimizedMessage({
    required String roomId,
    required String text,
    required String senderDisplayName,
    String? fileUrl,
    String? fileName,
  }) async {
    try {
      // Get current user for optimistic update
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Create optimistic message with real user data
      final optimisticMessage = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        senderId: currentUser.uid,
        senderDisplayName: senderDisplayName,
        senderEmail: currentUser.email ?? '',
        text: text,
        timestamp: Timestamp.now(),
        fileUrl: fileUrl,
        fileName: fileName,
      );

      // Update local cache immediately for instant UI feedback
      _updateMemoryCache(roomId, [optimisticMessage]);

      // Notify stream listeners immediately
      if (_streamControllers.containsKey(roomId)) {
        final optimizedMessages = _getOptimizedMessageList(roomId);
        _streamControllers[roomId]!.add(optimizedMessages);
      }

      // Send to server (this is the only blocking operation)
      await RealtimeChatService.sendMessage(
        roomId: roomId,
        text: text,
        fileUrl: fileUrl,
        fileName: fileName,
      );

      // Remove optimistic message after successful send
      // The real message will come through the real-time listener
      _removeOptimisticMessage(roomId, optimisticMessage.id!);
    } catch (e) {
      // Remove optimistic update on error and show the error
      if (_messageCache.containsKey(roomId)) {
        _messageCache[roomId]!.removeWhere(
          (key, msg) => msg.id?.startsWith('temp_') ?? false,
        );

        if (_streamControllers.containsKey(roomId)) {
          final optimizedMessages = _getOptimizedMessageList(roomId);
          _streamControllers[roomId]!.add(optimizedMessages);
        }
      }
      rethrow;
    }
  }

  /// Remove optimistic message after real message arrives
  static void _removeOptimisticMessage(String roomId, String tempId) {
    Timer(const Duration(milliseconds: 500), () {
      if (_messageCache.containsKey(roomId)) {
        _messageCache[roomId]!.remove(tempId);
      }
    });
  }

  /// Load older messages with pagination
  static Future<List<Message>> loadOlderMessages(
    String roomId, {
    Message? lastMessage,
  }) async {
    try {
      // Determine the last message for pagination
      Message? paginationMessage = lastMessage;
      if (paginationMessage == null && _messageCache.containsKey(roomId)) {
        final cachedMessages = _messageCache[roomId]!.values.toList();
        if (cachedMessages.isNotEmpty) {
          cachedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          paginationMessage = cachedMessages.first;
        }
      }

      if (paginationMessage == null) {
        return [];
      }

      // Load from server
      final olderMessages = await RealtimeChatService.loadOlderMessages(
        roomId,
        paginationMessage,
        limit: messageBatchSize,
      );

      // Update cache
      if (olderMessages.isNotEmpty) {
        _updateMemoryCache(roomId, olderMessages);

        // Update stream
        if (_streamControllers.containsKey(roomId)) {
          final optimizedMessages = _getOptimizedMessageList(roomId);
          _streamControllers[roomId]!.add(optimizedMessages);
        }
      }

      return olderMessages;
    } catch (e) {
      print('Error loading older messages: $e');
      return [];
    }
  }

  /// Get cached messages count for a room
  static int getCachedMessageCount(String roomId) {
    return _messageCache[roomId]?.length ?? 0;
  }

  /// Check if cache is fresh
  static bool isCacheFresh(String roomId) {
    final lastFetch = _lastFetchTimes[roomId];
    if (lastFetch == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastFetch) < cacheExpiryMs;
  }

  /// Preload messages for a room
  static Future<void> preloadMessages(String roomId) async {
    if (isCacheFresh(roomId)) return;

    try {
      final stream = getOptimizedMessagesStream(roomId);
      final subscription = stream.listen(null);

      // Automatically cancel after initial load
      Timer(const Duration(seconds: 2), () {
        subscription.cancel();
      });
    } catch (e) {
      print('Error preloading messages: $e');
    }
  }

  /// Clear cache for a specific room
  static void clearRoomCache(String roomId) {
    _messageCache.remove(roomId);
    _lastFetchTimes.remove(roomId);
    _debounceTimers[roomId]?.cancel();
    _debounceTimers.remove(roomId);
  }

  /// Clear all cache
  static void clearAllCache() {
    _messageCache.clear();
    _lastFetchTimes.clear();

    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();

    for (final controller in _streamControllers.values) {
      controller.close();
    }
    _streamControllers.clear();
  }

  /// Cleanup resources for a specific room
  static void _cleanupRoom(String roomId) {
    _streamControllers[roomId]?.close();
    _streamControllers.remove(roomId);
    _debounceTimers[roomId]?.cancel();
    _debounceTimers.remove(roomId);
    RealtimeChatService.disposeRoom(roomId);
  }

  /// Get memory usage statistics
  static Map<String, dynamic> getMemoryStats() {
    int totalMessages = 0;
    int totalRooms = _messageCache.length;

    for (final cache in _messageCache.values) {
      totalMessages += cache.length;
    }

    return {
      'totalRooms': totalRooms,
      'totalMessages': totalMessages,
      'activeStreams': _streamControllers.length,
      'activeTimers': _debounceTimers.length,
    };
  }

  /// Optimize cache based on usage patterns
  static void optimizeCache() {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Remove expired caches
    _lastFetchTimes.removeWhere((roomId, timestamp) {
      final isExpired = (now - timestamp) > cacheExpiryMs * 2;
      if (isExpired) {
        clearRoomCache(roomId);
      }
      return isExpired;
    });
  }

  /// Start periodic cache optimization
  static Timer? _optimizationTimer;
  static void startPeriodicOptimization() {
    _optimizationTimer?.cancel();
    _optimizationTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => optimizeCache(),
    );
  }

  /// Stop periodic cache optimization
  static void stopPeriodicOptimization() {
    _optimizationTimer?.cancel();
    _optimizationTimer = null;
  }

  /// Dispose all resources
  static void dispose() {
    clearAllCache();
    stopPeriodicOptimization();
    RealtimeChatService.dispose();
  }
}
