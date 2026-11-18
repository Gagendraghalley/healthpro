import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One sheet of rows as an Excel file (.xlsx), which Excel, Google Sheets and
/// Numbers open as it is: a bold heading row that stays at the top, with
/// filters, then the rows. Text stays text (a phone number keeps its +, and
/// nothing is taken for a formula); numbers are numbers; a [DateTime] is a
/// date (one at midnight) or a date and time, as written: pass Bhutan's.
class Spreadsheet {
  /// The sheet's tab: 31 characters at most, without []:*?/\.
  final String sheetName;
  final List<String> headings;
  final List<List<Object?>> rows;

  const Spreadsheet({required this.sheetName, required this.headings, required this.rows});

  static const mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// The .xlsx file's bytes.
  Uint8List toXlsx() {
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook))
      ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
      ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheetXml()));
    return ZipEncoder().encodeBytes(archive);
  }

  /// The worksheet's XML (xl/worksheets/sheet1.xml).
  String sheetXml() {
    final columns = headings.length;
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="$_main" xmlns:r="$_rel">')
      ..write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
      ..write('<cols>');
    for (var c = 0; c < columns; c++) {
      out.write('<col min="${c + 1}" max="${c + 1}" width="${_width(c)}" customWidth="1"/>');
    }
    out
      ..write('</cols><sheetData>')
      ..write(_row(1, headings, header: true));
    for (var r = 0; r < rows.length; r++) {
      out.write(_row(r + 2, rows[r]));
    }
    out.write('</sheetData>');
    if (columns > 0) out.write('<autoFilter ref="A1:${columnName(columns - 1)}${rows.length + 1}"/>');
    out.write('</worksheet>');
    return out.toString();
  }

  String _row(int number, List<Object?> cells, {bool header = false}) {
    final out = StringBuffer('<row r="$number">');
    for (var c = 0; c < cells.length; c++) {
      final ref = '${columnName(c)}$number';
      final value = cells[c];
      if (value == null || (value is String && value.isEmpty)) continue;
      if (value is num && !header) {
        if (value.isFinite) out.write('<c r="$ref"><v>$value</v></c>');
      } else if (value is DateTime && !header) {
        final timed = value.hour != 0 || value.minute != 0 || value.second != 0;
        out.write('<c r="$ref" s="${timed ? 3 : 2}"><v>${excelSerial(value)}</v></c>');
      } else {
        out.write('<c r="$ref" t="inlineStr"${header ? ' s="1"' : ''}>'
            '<is><t xml:space="preserve">${xmlText('$value')}</t></is></c>');
      }
    }
    out.write('</row>');
    return out.toString();
  }

  /// A column wide enough for its heading and most of its cells (in
  /// characters), 8 to 50.
  int _width(int column) {
    var widest = headings[column].length + 2;
    for (final row in rows.take(500)) {
      if (column >= row.length) continue;
      final v = row[column];
      final length = switch (v) {
        null => 0,
        DateTime d => d.hour != 0 || d.minute != 0 ? 17 : 12,
        _ => '$v'.length,
      };
      if (length + 2 > widest) widest = length + 2;
    }
    return widest.clamp(8, 50);
  }

  /// 0 -> 'A', 25 -> 'Z', 26 -> 'AA'.
  static String columnName(int index) {
    var n = index + 1;
    var name = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      name = String.fromCharCode(65 + r) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  /// Days since 30 December 1899, as Excel counts them, with the time as a
  /// fraction; [moment]'s fields as they are, whatever its time zone.
  static num excelSerial(DateTime moment) {
    final at = DateTime.utc(moment.year, moment.month, moment.day, moment.hour, moment.minute, moment.second);
    final seconds = at.difference(DateTime.utc(1899, 12, 30)).inSeconds;
    return seconds % 86400 == 0 ? seconds ~/ 86400 : seconds / 86400;
  }

  /// [text] safe inside XML: the five special characters escaped, and
  /// control characters XML can't hold dropped.
  static String xmlText(String text) => text
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  String get _safeSheetName {
    final name = sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    return xmlText(name.isEmpty ? 'Sheet1' : (name.length > 31 ? name.substring(0, 31) : name));
  }

  static const _main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  static const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="xl/workbook.xml"/>'
      '</Relationships>';

  String get _workbook => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="$_main" xmlns:r="$_rel"><sheets>'
      '<sheet name="$_safeSheetName" sheetId="1" r:id="rId1"/>'
      '</sheets></workbook>';

  static const _workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '</Relationships>';

  /// Styles: 0 plain, 1 bold (headings), 2 a date, 3 a date and time.
  static const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="$_main">'
      '<numFmts count="2"><numFmt numFmtId="164" formatCode="d mmm yyyy"/>'
      '<numFmt numFmtId="165" formatCode="d mmm yyyy h:mm"/></numFmts>'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}

/// [name] ('Peak Fitness members 2026-11-18.xlsx') without characters file
/// systems refuse.
String safeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
