class AppConfig {
  static const String proxyBaseUrl = 'https://chat.vymedia.xyz';

  static Uri get proxyChatUri {
    final base = Uri.parse(proxyBaseUrl);
    if (base.path.isEmpty || base.path == '/') {
      return base.replace(path: '/chat');
    }
    return base;
  }

  static const int maxMessageLength = 4000;
  static const int maxCustomInstructionsLength = 2000;
}
