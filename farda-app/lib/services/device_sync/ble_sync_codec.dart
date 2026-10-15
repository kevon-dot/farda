import 'dart:convert';

/// Bounded parser for the documented SYNC_DATA + JSON array framing.
/// Byte buffering preserves UTF-8 code points split between BLE notifications.
/// Parsing never implies that legacy events have sufficient stable identities.
class BleSyncCodec {
  BleSyncCodec({
    this.maxBytes = 64 * 1024,
    this.maxEvents = 256,
    this.frameTimeout = const Duration(seconds: 10),
  });

  final int maxBytes;
  final int maxEvents;
  final Duration frameTimeout;
  static final _prefix = ascii.encode('SYNC_DATA');
  final List<int> _buffer = [];
  DateTime? _started;
  bool _complete = false;
  int _cursor = 9;
  bool _jsonStarted = false;
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;

  void reset() {
    _buffer.clear();
    _started = null;
    _complete = false;
    _cursor = _prefix.length;
    _jsonStarted = false;
    _depth = 0;
    _inString = false;
    _escaped = false;
  }

  List<Map<String, dynamic>>? add(List<int> bytes, {required DateTime now}) {
    if (_complete) throw StateError('Frame already completed');
    if (bytes.isEmpty) return null;
    _started ??= now;
    if (now.difference(_started!) > frameTimeout) {
      throw const FormatException('BLE frame timed out');
    }
    if (bytes.any((byte) => byte < 0 || byte > 255) ||
        _buffer.length + bytes.length > maxBytes) {
      throw const FormatException('BLE frame exceeds bounds');
    }
    _buffer.addAll(bytes);
    for (var i = 0; i < _prefix.length && i < _buffer.length; i++) {
      if (_buffer[i] != _prefix[i]) {
        throw const FormatException('Unexpected BLE frame');
      }
    }
    if (_buffer.length <= _prefix.length) return null;

    var end = -1;
    for (var i = _cursor; i < _buffer.length; i++) {
      _cursor = i + 1;
      final byte = _buffer[i];
      if (!_jsonStarted) {
        if (_whitespace(byte)) continue;
        if (byte != 91) {
          throw const FormatException('BLE frame must contain an array');
        }
        _jsonStarted = true;
      }
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (byte == 92) {
          _escaped = true;
        } else if (byte == 34) {
          _inString = false;
        }
      } else if (byte == 34) {
        _inString = true;
      } else if (byte == 91 || byte == 123) {
        _depth++;
        if (_depth > 16) {
          throw const FormatException('BLE JSON nesting exceeds bound');
        }
      } else if (byte == 93 || byte == 125) {
        _depth--;
        if (_depth < 0) throw const FormatException('Unbalanced BLE JSON');
        if (_depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;
    if (_buffer.skip(end + 1).any((byte) => !_whitespace(byte))) {
      throw const FormatException('Trailing bytes after BLE frame');
    }
    final value = jsonDecode(
      utf8.decode(_buffer.sublist(_prefix.length, end + 1)),
    );
    if (value is! List ||
        value.length > maxEvents ||
        value.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Unsupported BLE events');
    }
    _complete = true;
    return value.cast<Map<String, dynamic>>();
  }

  static bool _whitespace(int byte) =>
      byte == 32 || byte == 9 || byte == 10 || byte == 13;
}
