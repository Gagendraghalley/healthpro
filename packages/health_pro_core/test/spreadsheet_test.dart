import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  const sheet = Spreadsheet(
    sheetName: 'Members: Nov/Dec',
    headings: ['Name', 'Phone', 'Joined', 'Visit', 'Paid'],
    rows: [
      ['Karma & <Sons>', '+97517123456', null, null, 4500],
      ['=HYPERLINK("x")', '', null, null, 12.5],
    ],
  );

  test('an .xlsx: a zip with the workbook, its sheet and styles', () {
    final zip = ZipDecoder().decodeBytes(sheet.toXlsx());
    expect(zip.files.map((f) => f.name),
        containsAll(['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/styles.xml']));
    final workbook = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
    expect(workbook, contains('name="Members  Nov Dec"'), reason: 'characters a tab name can\'t hold are dropped');
  });

  test('text stays text, escaped; numbers are numbers; nothing is a formula', () {
    final xml = sheet.sheetXml();
    expect(xml, contains('<c r="A1" t="inlineStr" s="1">'), reason: 'headings bold');
    expect(xml, contains('Karma &amp; &lt;Sons&gt;'));
    expect(xml, contains('<c r="B2" t="inlineStr"><is><t xml:space="preserve">+97517123456</t>'));
    expect(xml, contains('<c r="E2"><v>4500</v></c>'));
    expect(xml, contains('<c r="E3"><v>12.5</v></c>'));
    expect(xml, contains('=HYPERLINK(&quot;x&quot;)</t>'), reason: 'a string cell, never <f>');
    expect(xml, isNot(contains('<f>')));
    expect(xml, isNot(contains('r="B3"')), reason: 'empty cells are left out');
    expect(xml, contains('<autoFilter ref="A1:E3"/>'));
    expect(xml, contains('state="frozen"'));
  });

  test('dates are dates, and a time makes it a date and time', () {
    final xml = Spreadsheet(sheetName: 'x', headings: const ['Day', 'At'], rows: [
      [DateTime(2000, 1, 1), DateTime(2026, 11, 18, 18)],
    ]).sheetXml();
    expect(xml, contains('<c r="A2" s="2"><v>36526</v></c>'), reason: '1 January 2000 is day 36526');
    expect(xml, contains('<c r="B2" s="3"><v>${Spreadsheet.excelSerial(DateTime(2026, 11, 18)) + 0.75}</v></c>'));
  });

  test('column letters and file names', () {
    expect([0, 25, 26, 27, 51, 52, 701, 702].map(Spreadsheet.columnName), ['A', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
    expect(safeFileName('Peak: Fitness / members?  2026-11-18.xlsx'), 'Peak Fitness members 2026-11-18.xlsx');
    expect(Spreadsheet.xmlText('a\u0001b'), 'ab');
  });
}
