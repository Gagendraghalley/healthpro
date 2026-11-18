/// Printing a page is for the website: the phone apps share a picture
/// instead (it prints from the phone's gallery).
abstract final class PagePrinter {
  static bool get available => false;

  static void printHtml(String html) => throw UnsupportedError('Printing is on the website only.');
}
