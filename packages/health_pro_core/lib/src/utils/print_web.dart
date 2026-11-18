import 'dart:js_interop';

@JS('window.open')
external _Window? _open(String url, String target);

extension type _Window._(JSObject _) implements JSObject {
  external _Document get document;
  external void focus();
  external void print();
}

extension type _Document._(JSObject _) implements JSObject {
  external void open();
  external void write(String html);
  external void close();
}

/// Prints a page of HTML (a receipt) from the browser: it opens in a new
/// window, with the browser's print dialog over it.
abstract final class PagePrinter {
  static bool get available => true;

  static void printHtml(String html) {
    final window = _open('', '_blank');
    if (window == null) throw StateError('Allow pop-ups for this site, then print again.');
    window.document
      ..open()
      ..write(html)
      ..close();
    window
      ..focus()
      ..print();
  }
}
