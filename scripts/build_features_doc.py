#!/usr/bin/env python3
"""Builds docs/Health_Pro_Features.docx from docs/features.md (standard library only).

Run from anywhere: python3 scripts/build_features_doc.py
The Markdown it reads: '# ' title, '## ' and '### ' headings, '- ' bullets ('  - ' under one), paragraphs, **bold**.
Edit docs/features.md, never the .docx: this script overwrites it.
"""

import re
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'docs' / 'features.md'
OUTPUT = ROOT / 'docs' / 'Health_Pro_Features.docx'

FONT = 'Calibri'
NAVY = '0B1530'
BLUE = '1F6FD6'
MUTED = '5B6475'
FIXED_TIME = (2026, 1, 1, 0, 0, 0)  # same bytes for the same text, so git only sees real changes


def runs(text, color=None):
    """'**bold** rest' -> Word runs."""
    out = []
    for i, part in enumerate(re.split(r'\*\*(.+?)\*\*', text)):
        if not part:
            continue
        props = ('<w:b/>' if i % 2 else '') + (f'<w:color w:val="{color}"/>' if color else '')
        rpr = f'<w:rPr>{props}</w:rPr>' if props else ''
        out.append(f'<w:r>{rpr}<w:t xml:space="preserve">{escape(part)}</w:t></w:r>')
    return ''.join(out)


def paragraph(text, style=None, level=None, color=None):
    ppr = ''
    if style or level is not None:
        ppr = '<w:pPr>' + (f'<w:pStyle w:val="{style}"/>' if style else '')
        ppr += f'<w:numPr><w:ilvl w:val="{level}"/><w:numId w:val="1"/></w:numPr>' if level is not None else ''
        ppr += '</w:pPr>'
    return f'<w:p>{ppr}{runs(text.replace("`", ""), color)}</w:p>'


def body(markdown):
    paras = []
    for raw in markdown.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith('### '):
            paras.append(paragraph(line[4:], style='Heading2'))
        elif line.startswith('## '):
            paras.append(paragraph(line[3:], style='Heading1'))
        elif line.startswith('# '):
            paras.append(paragraph(line[2:], style='Title'))
        elif line.startswith('- '):
            # Two or more leading spaces: a bullet under the one above.
            level = 1 if raw.startswith('  ') else 0
            paras.append(paragraph(line[2:], style='ListParagraph', level=level))
        elif line.startswith('Last updated:'):
            paras.append(paragraph(line, color=MUTED))
        else:
            paras.append(paragraph(line))
    return ''.join(paras)


W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
R = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def document_xml(markdown):
    # A4, 2 cm margins.
    sect = ('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
            '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="709" w:footer="709" w:gutter="0"/>'
            '</w:sectPr>')
    return f'{HEAD}<w:document {W} {R}><w:body>{body(markdown)}{sect}</w:body></w:document>'


STYLES = f'''{HEAD}<w:styles {W}>
<w:docDefaults>
  <w:rPrDefault><w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}" w:eastAsia="{FONT}"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-GB"/></w:rPr></w:rPrDefault>
  <w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
  <w:pPr><w:keepNext/><w:spacing w:before="0" w:after="160"/><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="6" w:color="{BLUE}"/></w:pBdr></w:pPr>
  <w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}"/><w:b/><w:color w:val="{NAVY}"/><w:sz w:val="44"/><w:szCs w:val="44"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
  <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="320" w:after="100"/><w:outlineLvl w:val="0"/></w:pPr>
  <w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}"/><w:b/><w:color w:val="{BLUE}"/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
  <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="1"/></w:pPr>
  <w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}"/><w:b/><w:color w:val="{NAVY}"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/>
  <w:pPr><w:spacing w:after="60"/></w:pPr></w:style>
</w:styles>'''

NUMBERING = f'''{HEAD}<w:numbering {W}>
<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/>
    <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr><w:rPr><w:color w:val="{BLUE}"/></w:rPr></w:lvl>
  <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="–"/><w:lvlJc w:val="left"/>
    <w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr><w:rPr><w:color w:val="{BLUE}"/></w:rPr></w:lvl>
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>'''

CONTENT_TYPES = f'''{HEAD}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>'''

RELS = f'''{HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>'''

DOC_RELS = f'''{HEAD}<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>'''

CORE = f'''{HEAD}<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>Health Pro: features by role</dc:title><dc:creator>Health Pro</dc:creator>
</cp:coreProperties>'''


def main():
    markdown = SOURCE.read_text(encoding='utf-8')
    parts = {
        '[Content_Types].xml': CONTENT_TYPES,
        '_rels/.rels': RELS,
        'docProps/core.xml': CORE,
        'word/_rels/document.xml.rels': DOC_RELS,
        'word/document.xml': document_xml(markdown),
        'word/styles.xml': STYLES,
        'word/numbering.xml': NUMBERING,
    }
    with zipfile.ZipFile(OUTPUT, 'w', zipfile.ZIP_DEFLATED) as docx:
        for name, xml in parts.items():
            docx.writestr(zipfile.ZipInfo(name, FIXED_TIME), xml.encode('utf-8'), zipfile.ZIP_DEFLATED)
    print(f'Wrote {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    sys.exit(main())
