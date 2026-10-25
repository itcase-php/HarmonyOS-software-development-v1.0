"""Exercise the real OOXML inspector. This does not execute LibreOffice or a phone."""
import argparse
import json
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
P = 'http://schemas.openxmlformats.org/presentationml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PR = 'http://schemas.openxmlformats.org/package/2006/relationships'
parser = argparse.ArgumentParser()
parser.add_argument('cli', type=Path)
args = parser.parse_args()
OUT = ROOT / 'tmp/core-engines/font-usage'
OUT.mkdir(parents=True, exist_ok=True)
cases = []


def relations(items):
    return '<Relationships xmlns="' + PR + '">' + ''.join(
        f'<Relationship Id="{key}" Type="{R}/{kind}" Target="{target}"/>'
        for key, kind, target in items) + '</Relationships>'


def doc(body, extra=None, styles=''):
    parts = {'word/document.xml': f'<w:document xmlns:w="{W}" xmlns:r="{R}" xmlns:a="{A}"><w:body>{body}</w:body></w:document>'}
    if styles:
        parts['word/styles.xml'] = f'<w:styles xmlns:w="{W}">{styles}</w:styles>'
        parts['word/_rels/document.xml.rels'] = relations([('styles', 'styles', 'styles.xml')])
    parts.update(extra or {})
    return parts


def run(text='Hello', props='<w:rFonts w:ascii="DejaVu Sans"/>'):
    return f'<w:r><w:rPr>{props}</w:rPr><w:t>{text}</w:t></w:r>'


def check(name, parts, expected=(), failure=None, format='docx', includes=None):
    main = 'word/document.xml' if format == 'docx' else 'ppt/presentation.xml'
    content_type = 'wordprocessingml.document' if format == 'docx' else 'presentationml.presentation'
    path = OUT / (name + '.' + format)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        package.writestr('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            f'<Override PartName="/{main}" ContentType="application/vnd.openxmlformats-officedocument.{content_type}.main+xml"/></Types>')
        for part, content in parts.items():
            package.writestr(part, content)
    result = subprocess.run([str(args.cli.resolve()), format, str(path)], capture_output=True, text=True, encoding='utf-8')
    if failure:
        assert result.returncode != 0 and failure in result.stderr, (name, result.stdout, result.stderr)
    else:
        assert result.returncode == 0, (name, result.returncode, result.stderr)
        actual = {line[5:] for line in result.stdout.splitlines() if line.startswith('font=')}
        assert actual == set(expected), (name, 'effective families', actual, set(expected), result.stdout)
        for item in includes or []:
            assert item in result.stdout, (name, item, result.stdout)
    cases.append({'name': name, 'passed': True})


normal = '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:rPr><w:rFonts w:ascii="DejaVu Sans"/></w:rPr></w:style>'
unused = '<w:style w:type="paragraph" w:styleId="Unused"><w:rPr><w:rFonts w:ascii="Missing Unused Style"/></w:rPr></w:style>'
check('unused-style', doc('<w:p>' + run() + '</w:p>', styles=normal + unused), ['DejaVu Sans'])
check('unused-script-slot', doc('<w:p>' + run(props='<w:rFonts w:ascii="DejaVu Sans" w:eastAsia="Missing Unused CJK" w:cs="Missing Unused CS"/>') + '</w:p>'), ['DejaVu Sans'])
check('used-missing-family', doc('<w:p>' + run(props='<w:rFonts w:ascii="Missing Actually Used"/>') + '</w:p>'), ['Missing Actually Used'])
base = '<w:style w:type="paragraph" w:styleId="Base"><w:rPr><w:rFonts w:ascii="Base Font"/></w:rPr></w:style>'
child = '<w:style w:type="paragraph" w:styleId="Child"><w:basedOn w:val="Base"/></w:style>'
paragraph = '<w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr>'
check('paragraph-inheritance', doc(paragraph + run(props='') + '</w:p>', styles=base + child), ['Base Font'])
check('direct-overrides-style', doc(paragraph + run() + '</w:p>', styles=base + child), ['DejaVu Sans'])
char = '<w:style w:type="character" w:styleId="Emphasis"><w:rPr><w:rFonts w:ascii="Character Font"/></w:rPr></w:style>'
check('character-style', doc('<w:p>' + run(props='<w:rStyle w:val="Emphasis"/>') + '</w:p>', styles=normal + char), ['Character Font'])
defaults = '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Default Font"/></w:rPr></w:rPrDefault></w:docDefaults>'
check('document-default', doc('<w:p>' + run(props='') + '</w:p>', styles=defaults), ['Default Font'])
check('mixed-script', doc('<w:p>' + run('Hello 中文', '<w:rFonts w:ascii="Latin Font" w:eastAsia="Chinese Font" w:cs="Unused Complex Font"/>') + '</w:p>'), ['Latin Font', 'Chinese Font'])
check('complex-script', doc('<w:p>' + run('مرحبا', '<w:rFonts w:ascii="Unused Latin" w:cs="Arabic Font"/>') + '</w:p>'), ['Arabic Font'])
theme = f'<a:theme xmlns:a="{A}"><a:themeElements><a:fontScheme><a:majorFont><a:latin typeface="Major Font"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Hans" typeface="Major Chinese"/></a:majorFont><a:minorFont><a:latin typeface="Minor Font"/><a:ea typeface=""/><a:cs typeface=""/><a:font script="Hans" typeface="Minor Chinese"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>'
extra = {'word/theme/theme1.xml': theme, 'word/_rels/document.xml.rels': relations([('theme', 'theme', 'theme/theme1.xml')])}
check('unused-theme', doc('<w:p>' + run() + '</w:p>', extra), ['DejaVu Sans'])
check('used-theme', doc('<w:p>' + run('Hello 中文', '<w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorEastAsia"/>') + '</w:p>', extra), ['Minor Font', 'Minor Chinese'])
check('explicit-cross-script-theme', doc('<w:p>' + run('中文', '<w:rFonts w:eastAsiaTheme="minorAscii"/>') + '</w:p>', extra), ['Minor Font'])
check('unresolved-theme', doc('<w:p>' + run(props='<w:rFonts w:asciiTheme="minorHAnsi"/>') + '</w:p>'), failure='OFFICE_FONT_USAGE_UNRESOLVED')
header = f'<w:hdr xmlns:w="{W}"><w:p>{run(props="<w:rFonts w:ascii='Header Font'/>")}</w:p></w:hdr>'
check('used-header', doc('<w:p>' + run() + '</w:p><w:sectPr><w:headerReference r:id="header"/></w:sectPr>', {
    'word/header1.xml': header, 'word/header2.xml': header.replace('Header Font', 'Unused Header'),
    'word/_rels/document.xml.rels': relations([('header', 'header', 'header1.xml')])}), ['DejaVu Sans', 'Header Font'], includes=['font-part=word/header1.xml'])
numbering = f'<w:numbering xmlns:w="{W}"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:rPr><w:rFonts w:ascii="Number Font"/></w:rPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>'
extra_num = {'word/numbering.xml': numbering, 'word/_rels/document.xml.rels': relations([('num', 'numbering', 'numbering.xml')])}
check('unused-numbering', doc('<w:p>' + run() + '</w:p>', extra_num), ['DejaVu Sans'])
check('used-numbering', doc('<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>' + run() + '</w:p>', extra_num), ['DejaVu Sans', 'Number Font'])
check('private-symbol-binding', doc('<w:p>' + run('\ue000', '<w:rFonts w:ascii="Icon Font" w:hAnsi="Icon Font"/>') + '</w:p>', styles=unused), ['Icon Font'], includes=['private=1'])
check('word-symbol', doc('<w:p><w:r><w:sym w:font="Symbol Font" w:char="F0B7"/></w:r></w:p>'), ['Symbol Font'], includes=['private=1'])
cycle = base.replace('<w:rPr>', '<w:basedOn w:val="Child"/><w:rPr>') + child
check('style-cycle', doc(paragraph + run(props='') + '</w:p>', styles=cycle), failure='OFFICE_FONT_USAGE_UNRESOLVED')
# Security still examines unused parts.
check('unused-protected-part', doc('<w:p>' + run() + '</w:p>', {'word/unused.xml': '<settings><documentProtection/></settings>'}), failure='NATIVE_OFFICE_PROTECTED')
table_style = '<w:style w:type="table" w:styleId="TableFont"><w:rPr><w:rFonts w:ascii="Table Font"/></w:rPr></w:style>'
check('table-font', doc('<w:tbl><w:tblPr><w:tblStyle w:val="TableFont"/></w:tblPr><w:tr><w:tc><w:p>' + run(props='') + '</w:p></w:tc></w:tr></w:tbl>', styles=table_style), ['Table Font'])
check('table-direct-overrides', doc('<w:tbl><w:tblPr><w:tblStyle w:val="TableFont"/></w:tblPr><w:tr><w:tc><w:p>' + run() + '</w:p></w:tc></w:tr></w:tbl>', styles=table_style), ['DejaVu Sans'])
check('inactive-first-header', doc('<w:p>' + run() + '</w:p><w:sectPr><w:headerReference w:type="first" r:id="header"/></w:sectPr>', {
    'word/header1.xml': header, 'word/_rels/document.xml.rels': relations([('header', 'header', 'header1.xml')])}), ['DejaVu Sans'])
check('active-first-header', doc('<w:p>' + run() + '</w:p><w:sectPr><w:headerReference w:type="first" r:id="header"/><w:titlePg/></w:sectPr>', {
    'word/header1.xml': header, 'word/_rels/document.xml.rels': relations([('header', 'header', 'header1.xml')])}), ['DejaVu Sans', 'Header Font'])
check('unused-even-header', doc('<w:p>' + run() + '</w:p><w:sectPr><w:headerReference w:type="even" r:id="header"/></w:sectPr>', {
    'word/header1.xml': header, 'word/_rels/document.xml.rels': relations([('header', 'header', 'header1.xml')])}), ['DejaVu Sans'])
notes = f'<w:footnotes xmlns:w="{W}"><w:footnote w:id="1"><w:p>{run(props="<w:rFonts w:ascii='Note Font'/>")}</w:p></w:footnote><w:footnote w:id="2"><w:p>{run(props="<w:rFonts w:ascii='Unused Note'/>")}</w:p></w:footnote></w:footnotes>'
check('referenced-footnote', doc('<w:p>' + run() + '<w:r><w:footnoteReference w:id="1"/></w:r></w:p>', {
    'word/footnotes.xml': notes, 'word/_rels/document.xml.rels': relations([('notes', 'footnotes', 'footnotes.xml')])}), ['DejaVu Sans', 'Note Font'])
check('empty-run-ignored', doc('<w:p>' + run() + run('', '<w:rFonts w:ascii="Missing Empty Run"/>') + '</w:p>'), ['DejaVu Sans'])
check('explicit-font-overrides-theme', doc('<w:p>' + run(props='<w:rFonts w:ascii="DejaVu Sans"/>') + '</w:p>', extra, defaults.replace('w:ascii="Default Font"', 'w:asciiTheme="minorHAnsi"')), ['DejaVu Sans'])


def ppt(text='<a:r><a:rPr><a:latin typeface="DejaVu Sans"/></a:rPr><a:t>Hello</a:t></a:r>', extra=None, paragraph_props=''):
    parts = {
        'ppt/presentation.xml': f'<p:presentation xmlns:p="{P}" xmlns:r="{R}"><p:sldIdLst><p:sldId id="256" r:id="slide"/></p:sldIdLst></p:presentation>',
        'ppt/_rels/presentation.xml.rels': relations([('slide', 'slide', 'slides/slide1.xml')]),
        'ppt/slides/slide1.xml': f'<p:sld xmlns:p="{P}" xmlns:a="{A}"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:cNvPr id="2"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p>{paragraph_props}{text}</a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>'}
    parts.update(extra or {})
    return parts


check('ppt-unused-theme', ppt(extra={'ppt/theme/theme1.xml': theme}), ['DejaVu Sans'], format='pptx')
master = f'<p:sldMaster xmlns:p="{P}" xmlns:a="{A}"><p:cSld><p:spTree/></p:cSld><p:txStyles><p:bodyStyle><a:lvl1pPr><a:defRPr><a:latin typeface="Master Font"/></a:defRPr></a:lvl1pPr></p:bodyStyle></p:txStyles></p:sldMaster>'
layout = f'<p:sldLayout xmlns:p="{P}" xmlns:a="{A}"><p:cSld><p:spTree/></p:cSld></p:sldLayout>'
links = {'ppt/slides/_rels/slide1.xml.rels': relations([('layout', 'slideLayout', '../slideLayouts/slideLayout1.xml')]),
    'ppt/slideLayouts/slideLayout1.xml': layout,
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels': relations([('master', 'slideMaster', '../slideMasters/slideMaster1.xml')]),
    'ppt/slideMasters/slideMaster1.xml': master}
check('ppt-master-inheritance', ppt('<a:r><a:t>Hello</a:t></a:r>', links), ['Master Font'], format='pptx')
check('ppt-direct-overrides-master', ppt(extra=links), ['DejaVu Sans'], format='pptx')
title_links = dict(links)
title_links['ppt/slideLayouts/slideLayout1.xml'] = layout.replace('<p:spTree/>', '<p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p/></p:txBody></p:sp></p:spTree>')
title_links['ppt/slideMasters/slideMaster1.xml'] = master.replace('<p:bodyStyle>', '<p:titleStyle><a:lvl1pPr><a:defRPr><a:latin typeface="Title Font"/></a:defRPr></a:lvl1pPr></p:titleStyle><p:bodyStyle>')
title_parts = ppt('<a:r><a:t>Hello</a:t></a:r>', title_links)
title_parts['ppt/slides/slide1.xml'] = title_parts['ppt/slides/slide1.xml'].replace('<p:ph type="body" idx="1"/>', '<p:ph/>')
check('ppt-placeholder-type-inherited', title_parts, ['Title Font'], format='pptx')
theme_links = dict(links, **{'ppt/slideMasters/_rels/slideMaster1.xml.rels': relations([('theme', 'theme', '../theme/theme1.xml')]), 'ppt/theme/theme1.xml': theme})
check('ppt-theme', ppt('<a:r><a:rPr><a:latin typeface="+mn-lt"/></a:rPr><a:t>Hello</a:t></a:r>', theme_links), ['Minor Font'], format='pptx')
check('ppt-unused-slide', ppt(extra={'ppt/slides/slide2.xml': f'<p:sld xmlns:p="{P}" xmlns:a="{A}"><a:p><a:r><a:rPr><a:latin typeface="Unused Slide"/></a:rPr><a:t>Unused</a:t></a:r></a:p></p:sld>'}), ['DejaVu Sans'], format='pptx')
check('ppt-bullet', ppt(extra=None, paragraph_props='<a:pPr><a:buFont typeface="Bullet Font"/><a:buChar char="•"/></a:pPr>'), ['DejaVu Sans', 'Bullet Font'], format='pptx')
check('ppt-used-master-shape', ppt(extra=dict(links, **{'ppt/slideMasters/slideMaster1.xml': master.replace('<p:spTree/>', f'<p:spTree><p:sp><p:txBody><a:p><a:r><a:rPr><a:latin typeface="Visible Master Font"/></a:rPr><a:t>Footer</a:t></a:r></a:p></p:txBody></p:sp></p:spTree>')})), ['DejaVu Sans', 'Visible Master Font'], format='pptx')
report = {'scope': 'actual native OOXML font usage inspection; no device conversion', 'passed': len(cases), 'cases': cases}
(ROOT / 'tests/generated/office-font-usage.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'passed': len(cases), 'device': 'not executed'}))
