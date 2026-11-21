import 'dart:js_interop';

@JS('history')
external _History get _history;

extension type _History._(JSObject _) implements JSObject {
  external JSAny? get state;
  external void replaceState(JSAny? data, String unused, String url);
}

/// Shows [url] in the address bar without loading it or adding a Back step.
/// Keeps the entry's state (Flutter's own, for Back and Forward).
void replaceWebAddress(String url) => _history.replaceState(_history.state, '', url);
