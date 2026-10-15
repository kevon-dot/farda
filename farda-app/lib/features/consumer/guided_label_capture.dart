import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../consumer_v2/design_system/farda_consumer_tokens.dart';
import 'consumer_controller.dart';
import 'data/consumer_models.dart';
import 'data/label_scan.dart';

/// A bounded, explicit-upload capture flow. No photos are submitted on capture.
class GuidedLabelCaptureScreen extends StatefulWidget {
  const GuidedLabelCaptureScreen({
    super.key,
    required this.controller,
    this.takePhoto,
    this.choosePhoto,
  });
  final ConsumerController controller;
  final Future<LabelPhoto?> Function(BuildContext)? takePhoto;
  final Future<LabelPhoto?> Function()? choosePhoto;

  @override
  State<GuidedLabelCaptureScreen> createState() =>
      _GuidedLabelCaptureScreenState();
}

class _GuidedLabelCaptureScreenState extends State<GuidedLabelCaptureScreen> {
  final List<LabelPhoto> _photos = [];
  bool _covered = false;
  bool _busy = false;
  bool _reading = false;
  String? _error;
  int _generation = 0;

  void _manual() {
    ++_generation;
    Navigator.pop(context, const LabelScanDraft(manualEntry: true));
  }

  Future<void> _add({bool gallery = false, int? replace}) async {
    if (_busy || (replace == null && _photos.length >= 4)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      LabelPhoto? photo;
      if (gallery) {
        if (widget.choosePhoto != null) {
          photo = await widget.choosePhoto!();
        } else {
          final file = await ImagePicker().pickImage(
            source: ImageSource.gallery,
          );
          if (file != null) photo = await _readPhoto(file);
        }
      } else if (widget.takePhoto != null) {
        photo = await widget.takePhoto!(context);
      } else {
        final result = await Navigator.of(context).push<_CaptureResult>(
          MaterialPageRoute(
            builder:
                (_) => LabelViewfinderScreen(
                  photoNumber:
                      replace == null ? _photos.length + 1 : replace + 1,
                ),
          ),
        );
        if (!mounted) return;
        if (result?.manual == true) {
          _manual();
          return;
        }
        photo = result?.photo;
      }
      if (!mounted || photo == null) return;
      if (photo.validationError != null) {
        setState(() => _error = photo!.validationError);
        return;
      }
      setState(() {
        if (replace == null) {
          _photos.add(photo!);
        } else {
          unawaited(MemoryImage(_photos[replace].bytes).evict());
          _photos[replace] = photo!;
        }
        _covered = false;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'That photo could not be opened. Try another, or enter manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() async {
    if (_busy || !_covered || _photos.isEmpty) return;
    final repository = widget.controller.repository;
    if (repository is! LabelScanRepository) {
      setState(
        () =>
            _error =
                'Scanning is unavailable in this session. You can enter the label manually.',
      );
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _reading = true;
      _error = null;
    });
    try {
      final draft = await (repository as LabelScanRepository).extractLabel(
        List.unmodifiable(_photos),
      );
      if (!mounted ||
          generation != _generation ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      Navigator.pop(context, draft);
    } on ConsumerRepositoryException catch (e) {
      if (!mounted || generation != _generation) return;
      if (e.sessionExpired) {
        for (final photo in _photos) {
          unawaited(MemoryImage(photo.bytes).evict());
        }
        _photos.clear();
        _covered = false;
        // Clear the parent account view through its existing authenticated load.
        unawaited(widget.controller.load());
      }
      setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error =
                  'We could not read the label. Try again or enter manually. Nothing was saved.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _reading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    for (final photo in _photos) {
      unawaited(MemoryImage(photo.bytes).evict());
    }
    _photos.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: FardaConsumerTheme.from(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Scan your label'),
        backgroundColor: FardaConsumerColors.canvas,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          children: [
            Text(
              _photos.isEmpty
                  ? 'Every word,\nin view.'
                  : 'Have we got\nthe whole label?',
              style: FardaConsumerType.display,
            ),
            const SizedBox(height: 12),
            Text(
              _photos.isEmpty
                  ? 'One label at a time. Use up to four photos for long or curved labels.'
                  : 'Zoom in to check the small print. Add another view if any text is missing.',
              style: FardaConsumerType.body,
            ),
            const SizedBox(height: 20),
            if (_photos.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: FardaConsumerColors.brand,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.document_scanner_outlined,
                      size: 64,
                      color: FardaConsumerColors.mint,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Start with the name + directions',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Then turn the bottle slowly, or move along the label. Repeat a few lines in each photo.',
                      style: FardaConsumerType.body.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              for (var i = 0; i < _photos.length; i++) ...[
                _PhotoCard(
                  photo: _photos[i],
                  number: i + 1,
                  busy: _busy,
                  onRetake: () => _add(replace: i),
                  onRemove:
                      () => setState(() {
                        unawaited(MemoryImage(_photos[i].bytes).evict());
                        _photos.removeAt(i);
                        _covered = false;
                        _error = null;
                      }),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                '${_photos.length} of 4 photos · same label',
                style: FardaConsumerType.caption,
              ),
            ],
            const SizedBox(height: 16),
            if (_photos.length < 4) ...[
              FilledButton.icon(
                onPressed: _busy ? null : () => _add(),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _photos.isEmpty ? 'Take first photo' : 'Add another view',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _add(gallery: true),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose a photo'),
              ),
            ] else
              const Text(
                'Still missing text? Retake a view with more overlap, or enter the details manually.',
                style: FardaConsumerType.body,
              ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _covered,
                title: const Text(
                  'I can read all the label text across these photos.',
                  style: FardaConsumerType.body,
                ),
                subtitle: const Text(
                  'Check edges, directions and the text around the bottle.',
                  style: FardaConsumerType.caption,
                ),
                onChanged:
                    _busy
                        ? null
                        : (value) => setState(() => _covered = value ?? false),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy || !_covered ? null : _read,
                style: FilledButton.styleFrom(
                  backgroundColor: FardaConsumerColors.mint,
                  foregroundColor: FardaConsumerColors.brand,
                ),
                child: Text(
                  _reading ? 'Reading your label…' : 'Review label details',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This sends these photos for AI text extraction. You will check the details before anything is saved.',
                style: FardaConsumerType.caption,
              ),
            ],
            if (_reading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: FardaConsumerType.body.copyWith(
                      color: FardaConsumerColors.textWarm,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _manual,
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Enter manually instead'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.number,
    required this.busy,
    required this.onRetake,
    required this.onRemove,
  });
  final LabelPhoto photo;
  final int number;
  final bool busy;
  final VoidCallback onRetake;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => FardaConsumerCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('View $number', style: FardaConsumerType.bodyStrong),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: 'Enlarge photo $number to check the label',
          child: InkWell(
            onTap:
                busy
                    ? null
                    : () => showDialog<void>(
                      context: context,
                      builder:
                          (context) => Dialog.fullscreen(
                            child: Scaffold(
                              appBar: AppBar(
                                title: Text('Check photo $number'),
                              ),
                              body: InteractiveViewer(
                                minScale: 1,
                                maxScale: 5,
                                child: Center(
                                  child: Image.memory(
                                    photo.bytes,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                photo.bytes,
                height: 132,
                fit: BoxFit.contain,
                semanticLabel: 'Label photo $number',
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onRetake,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retake'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<LabelPhoto> _readPhoto(XFile file) async {
  if (await file.length() > 8 * 1024 * 1024) {
    throw const FormatException('Photo too large');
  }
  final bytes = await file.readAsBytes();
  final mime = LabelPhoto.detectMime(bytes);
  if (mime == null) throw const FormatException('Unsupported photo');
  return LabelPhoto(bytes: bytes, mimeType: mime);
}

class _CaptureResult {
  const _CaptureResult({this.photo, this.manual = false});
  final LabelPhoto? photo;
  final bool manual;
}

/// A real camera preview with framing guidance, not an automatic coverage claim.
class LabelViewfinderScreen extends StatefulWidget {
  const LabelViewfinderScreen({super.key, required this.photoNumber});
  final int photoNumber;
  @override
  State<LabelViewfinderScreen> createState() => _LabelViewfinderScreenState();
}

class _LabelViewfinderScreenState extends State<LabelViewfinderScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _initializing = false;
  bool _taking = false;
  String? _error;
  int _generation = 0;
  bool _active = true;
  Future<void> _closing = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || _camera != null || !_active) return;
    final generation = ++_generation;
    setState(() {
      _initializing = true;
      _error = null;
    });
    CameraController? controller;
    try {
      await _closing;
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('unavailable', 'No camera');
      final back = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      controller = CameraController(
        back.isEmpty ? cameras.first : back.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        /* Some cameras have no flash. */
      }
      if (!mounted || !_active || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (_) {
      await controller?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _initializing = false;
          _error =
              'Camera unavailable. Check camera access in Settings, choose an existing photo, or enter manually.';
        });
      }
    } finally {
      _initializing = false;
      if (mounted && _active && generation != _generation) {
        unawaited(_initialize());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _active = false;
      ++_generation;
      final camera = _camera;
      _camera = null;
      _closing = camera?.dispose() ?? _closing;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _active = true;
      _initialize();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _taking) return;
    setState(() {
      _taking = true;
      _error = null;
    });
    final generation = _generation;
    XFile? photo;
    try {
      photo = await camera.takePicture();
      final result = await _readPhoto(photo);
      if (mounted &&
          _active &&
          generation == _generation &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, _CaptureResult(photo: result));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _taking = false;
          _error = 'Photo not captured. Try again, or enter manually.';
        });
      }
    } finally {
      if (mounted) setState(() => _taking = false);
      // Only camera-owned temporary files are deleted. Selected library originals
      // are never deleted or modified.
      if (!kIsWeb && photo != null) {
        try {
          await File(photo.path).delete();
        } catch (_) {
          /* Best-effort cache cleanup. */
        }
      }
    }
  }

  @override
  void dispose() {
    _active = false;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: FardaConsumerTheme.from(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: Text('Photo ${widget.photoNumber} of 4'),
        backgroundColor: FardaConsumerColors.canvas,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          children: [
            const Text(
              'Give every line\na little room.',
              style: FardaConsumerType.heading,
            ),
            const SizedBox(height: 10),
            Text(
              widget.photoNumber == 1
                  ? 'Start with the medication name and full directions.'
                  : 'Turn the bottle or move along the label. Include a few lines from your last photo.',
              style: FardaConsumerType.body,
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 3 / 2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: FardaConsumerColors.deep,
                      child:
                          _camera == null
                              ? Center(
                                child:
                                    _initializing
                                        ? const CircularProgressIndicator(
                                          color: FardaConsumerColors.mint,
                                        )
                                        : const Icon(
                                          Icons.camera_alt_outlined,
                                          size: 48,
                                          color: Colors.white,
                                        ),
                              )
                              : Center(child: CameraPreview(_camera!)),
                    ),
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: FardaConsumerColors.mint,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Keep text sharp, avoid glare, and leave space around the edges.',
              style: FardaConsumerType.bodyStrong,
            ),
            const SizedBox(height: 6),
            const Text(
              'The outline is a guide. We keep the whole photo.',
              style: FardaConsumerType.caption,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _camera == null || _taking ? null : _capture,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_taking ? 'Capturing…' : 'Capture photo'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: FardaConsumerType.body),
              ),
              OutlinedButton(
                onPressed: _initializing ? null : _initialize,
                child: const Text('Try camera again'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to photos'),
            ),
            TextButton(
              onPressed:
                  () => Navigator.pop(
                    context,
                    const _CaptureResult(manual: true),
                  ),
              child: const Text('Enter manually instead'),
            ),
          ],
        ),
      ),
    ),
  );
}
