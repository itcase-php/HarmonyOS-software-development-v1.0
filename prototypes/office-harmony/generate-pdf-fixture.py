"""Synthetic text/image PDF; requires an explicit licensed test font path."""
import sys
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

root = Path(__file__).resolve().parents[2] / 'tmp/offline-engines/office-fixtures'
pdfmetrics.registerFont(TTFont('DejaVu Sans', sys.argv[1]))
pdf = canvas.Canvas(str(root / 'editable-input.pdf'), pagesize=(612, 792))
for number in [1, 2]:
    pdf.setFont('DejaVu Sans', 20)
    pdf.drawString(40, 720, 'Editable PDF page ' + str(number))
    pdf.setFont('DejaVu Sans', 14)
    pdf.drawString(40, 670, 'Key value 12345. Total 678.90.')
    pdf.drawImage(str(root / 'shapes.png'), 40, 450, width=240, height=100)
    pdf.showPage()
pdf.save()
