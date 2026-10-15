String canonicalApiRoot(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.split('/').contains('..')) {
    throw StateError('Configure an HTTPS API URL without credentials or query');
  }
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path != '/api') throw StateError('API URL must end in /api');
  return uri.replace(path: path).toString();
}

Uri apiUri(String base, String endpoint, {Map<String, String>? query}) {
  final root = canonicalApiRoot(base);
  final path = endpoint.replaceFirst(RegExp(r'^/+'), '');
  final candidate = Uri.parse(path);
  if (candidate.hasScheme ||
      candidate.hasAuthority ||
      candidate.hasQuery ||
      candidate.hasFragment ||
      candidate.pathSegments.any((part) => part == '..' || part == '.')) {
    throw ArgumentError('An API-relative endpoint is required');
  }
  return Uri.parse('$root/$path').replace(queryParameters: query);
}
