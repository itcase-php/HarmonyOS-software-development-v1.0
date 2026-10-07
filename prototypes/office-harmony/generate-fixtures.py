"""Repository-owned editable Office fixtures for device conversion acceptance."""
from pathlib import Path
from docx import Document
from docx.shared import Inches, Pt
from pptx import Presentation
from pptx.util import Inches as SlideInches, Pt as SlidePt
from PIL import Image, ImageDraw
import json

root = Path(__file__).resolve().parents[2] / 'tmp/offline-engines/office-fixtures'
root.mkdir(parents=True, exist_ok=True)
image = Image.new('RGB', (240, 100), '#e7eef8')
draw = ImageDraw.Draw(image)
draw.rectangle((15, 15, 95, 85), fill='#1260b8')
draw.ellipse((125, 15, 205, 85), fill='#c46014')
image.save(root / 'shapes.png')
doc = Document()
doc.styles['Normal'].font.name = 'DejaVu Sans'
doc.styles['Normal'].font.size = Pt(12)
for name in ['Title', 'Heading 1', 'Heading 2']:
    doc.styles[name].font.name = 'DejaVu Sans'
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.5), Inches(11)
section.header.paragraphs[0].text = 'OFFLINE OFFICE TEST'
doc.add_heading('Harmony Office Conversion', 0)
doc.add_paragraph('Editable document sample 12345. The total must remain 678.90.')
table = doc.add_table(rows=3, cols=3)
for row, values in zip(table.rows, [('Item', 'Count', 'Value'), ('Alpha', '2', '123.45'), ('Beta', '3', '555.45')]):
    for cell, value in zip(row.cells, values):
        cell.text = value
doc.add_picture(str(root / 'shapes.png'), width=Inches(3))
doc.add_page_break()
doc.add_heading('Second Page', level=1)
doc.add_paragraph('Page two keeps its manual page break and the key value 98765.')
doc.save(root / 'layout.docx')
deck = Presentation()
deck.slide_width, deck.slide_height = SlideInches(13.333333), SlideInches(7.5)
for index, title in enumerate(['Harmony Presentation', 'Editable Objects']):
    slide = deck.slides.add_slide(deck.slide_layouts[6])
    box = slide.shapes.add_textbox(SlideInches(0.7), SlideInches(0.5), SlideInches(12), SlideInches(1))
    paragraph = box.text_frame.paragraphs[0]
    paragraph.text = title
    paragraph.font.name, paragraph.font.size = 'DejaVu Sans', SlidePt(32)
    box = slide.shapes.add_textbox(SlideInches(0.7), SlideInches(1.8), SlideInches(10), SlideInches(1))
    paragraph = box.text_frame.paragraphs[0]
    paragraph.text = 'Key value 12345. Total 678.90. Slide ' + str(index + 1)
    paragraph.font.name, paragraph.font.size = 'DejaVu Sans', SlidePt(20)
    slide.shapes.add_picture(str(root / 'shapes.png'), SlideInches(0.7), SlideInches(3), width=SlideInches(4.8))
    table = slide.shapes.add_table(2, 2, SlideInches(6), SlideInches(3), SlideInches(5), SlideInches(2)).table
    for row, values in zip(table.rows, [('Item', 'Value'), ('Alpha', '678.90')]):
        for cell, value in zip(row.cells, values):
            cell.text = value
            for paragraph in cell.text_frame.paragraphs:
                paragraph.font.name, paragraph.font.size = 'DejaVu Sans', SlidePt(18)
deck.save(root / 'layout.pptx')
(root / 'expected.json').write_text(json.dumps({
    'docx': {'pages': 2, 'sizePt': [612, 792], 'requiredText': ['Harmony Office Conversion', '678.90', 'Second Page', '98765']},
    'pptx': {'pages': 2, 'sizePt': [960, 540], 'requiredText': ['Harmony Presentation', 'Editable Objects', '12345', '678.90']},
    'fixtureFont': 'DejaVu Sans', 'imageObjectsPerPageOrSlide': [1, 0],
}, indent=2) + '\n', encoding='utf-8')
print(root)
