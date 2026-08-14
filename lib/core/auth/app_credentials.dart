import 'dart:convert';

/// Built-in single-user credentials. Fragments are base64 so plaintext is not
/// sitting in the binary as one obvious string; assembled only at runtime.
class AppCredentials {
  const AppCredentials._();

  static const _uf = ['bW9u', 'aXNo'];
  static const _pf = ['Q2hlbm5haXN1', 'cGVyLjIz'];

  static String get username => utf8.decode(base64Decode(_uf.join()));

  static String get password => utf8.decode(base64Decode(_pf.join()));
}
