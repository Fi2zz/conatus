bool matchesMspPath(String pattern, String path) {
  if (pattern == path) return true;
  if (pattern.endsWith('.**')) {
    final String prefix = pattern.substring(0, pattern.length - 3);
    return path == prefix || path.startsWith('$prefix.');
  }
  if (pattern.endsWith('.*')) {
    final String prefix = pattern.substring(0, pattern.length - 2);
    if (!path.startsWith('$prefix.')) return false;
    return !path.substring(prefix.length + 1).contains('.');
  }
  return false;
}
