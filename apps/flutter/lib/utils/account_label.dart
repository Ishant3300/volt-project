/// One way to show an account everywhere (screens, PDFs, share text):
/// "Name (ID)", e.g. "AR126 (492267)". The ID is the account's username.
/// Falls back to whichever one exists; never repeats the same value twice.
String accountLabel(Object? name, Object? id) {
  final n = (name ?? '').toString().trim();
  final i = (id ?? '').toString().trim();
  if (n.isEmpty) return i;
  if (i.isEmpty || n == i) return n;
  return '$n ($i)';
}

/// [accountLabel] made safe for a file name ("AR126_(492267)").
String accountFileLabel(Object? name, Object? id) =>
    accountLabel(name, id).replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
