enum AppRoute {
  splash('/'),
  login('/login'),
  inbox('/inbox'),
  messageDetail('/message/:id'),
  compose('/compose'),
  settings('/settings');

  const AppRoute(this.path);

  final String path;
}
