"""Build the preliminary proposal and its labeled figures from the reviewed manuscript."""
from __future__ import annotations
import json
import logging
import math
import re
import subprocess
from pathlib import Path
from xml.sax.saxutils import escape
from PIL import Image, ImageDraw, ImageFont
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor, Color
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage, PageBreak, KeepTogether
from reportlab.graphics.shapes import Drawing, Rect, String, PolyLine, Polygon
from reportlab.graphics import renderPDF, renderSVG
from pypdf import PdfReader

logging.basicConfig(level=logging.INFO, format='%(message)s')
ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'PRELIMINARY_DESIGN_SPEC.md').is_file())
OUT = ROOT / 'output/pdf'
FIG = OUT / 'figures/v08'
TMP = ROOT / 'tmp/pdfs/preliminary_v08'
for folder in (OUT, FIG, TMP):
    folder.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont('YH', 'C:/Windows/Fonts/msyh.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('YHB', 'C:/Windows/Fonts/msyhbd.ttc', subfontIndex=0))
pdfmetrics.registerFontFamily('YH', normal='YH', bold='YHB', italic='YH', boldItalic='YHB')
INK = HexColor('#182B3B')
MUTED = HexColor('#536779')
LINE = HexColor('#CFD9E0')
TEAL = HexColor('#146F78')
WARM = HexColor('#996616')
PALE = HexColor('#EEF6F6')
AMBER = HexColor('#FCF4E5')
GRAY = HexColor('#F2F5F7')
WHITE = HexColor('#FFFFFF')
WIDTH = 507.28

from diagram_source import build_diagrams, save_vectors
DIAGRAMS=build_diagrams()
save_vectors(DIAGRAMS,FIG)
for name in DIAGRAMS:
    subprocess.run(['pdftoppm','-png','-singlefile','-r','300',str(FIG/f'{name}.pdf'),str(FIG/name)],check=True,capture_output=True)

styles={
 'quote':ParagraphStyle('quote',fontName='YHB',fontSize=16,leading=23,textColor=TEAL,spaceBefore=2,spaceAfter=12,wordWrap='CJK'),
 'title':ParagraphStyle('title',fontName='YHB',fontSize=28,leading=36,textColor=INK,spaceAfter=8),
 'h2':ParagraphStyle('h2',fontName='YHB',fontSize=14,leading=20,textColor=TEAL,spaceBefore=10,spaceAfter=10,wordWrap='CJK',keepWithNext=True),
 'h3':ParagraphStyle('h3',fontName='YHB',fontSize=11.5,leading=17,textColor=INK,spaceBefore=10,spaceAfter=7,wordWrap='CJK',keepWithNext=True),
 'body':ParagraphStyle('body',fontName='YH',fontSize=10,leading=16,textColor=INK,spaceAfter=7,wordWrap='CJK'),
 'caption':ParagraphStyle('caption',fontName='YH',fontSize=8,leading=12,textColor=MUTED,spaceAfter=8,wordWrap='CJK'),
 'cell':ParagraphStyle('cell',fontName='YH',fontSize=8.6,leading=13,textColor=INK,wordWrap='CJK'),
 'headcell':ParagraphStyle('headcell',fontName='YHB',fontSize=8.6,leading=13,textColor=INK,wordWrap='CJK'),
 'bullet':ParagraphStyle('bullet',fontName='YH',fontSize=10,leading=16,textColor=INK,spaceAfter=6,leftIndent=12,firstLineIndent=-9,wordWrap='CJK'),
}

def rich(text: str) -> str:
    value=escape(text)
    value=re.sub(r'\*\*(.+?)\*\*',r'<b>\1</b>',value)
    return value

def footer(canvas: object, doc: object) -> None:
    canvas.saveState()
    canvas.setStrokeColor(LINE);canvas.setLineWidth(.5)
    canvas.line(44,42,551,42)
    canvas.setFont('YH',7.5);canvas.setFillColor(MUTED)
    canvas.drawString(44,28,'nekoToken  /  请本人到场  /  玩法说明版 v0.8 · 2026.11.16')
    canvas.drawRightString(551,28,str(doc.page))
    canvas.restoreState()

source=OUT/'AI_PLAY_72H_预赛方案_精炼特色版_v0.8.md'
lines=source.read_text(encoding='utf-8').splitlines()
story=[];i=0
while i<len(lines):
    s=lines[i].strip()
    if not s:
        i+=1;continue
    if s=='<!-- page-break -->':
        story.append(PageBreak());i+=1;continue
    if s.startswith('> '):
        story.append(Paragraph(rich(s[2:]),styles['quote']));i+=1;continue
    if s.startswith('!['):
        match=re.fullmatch(r'!\[(.*?)\]\((.*?)\)',s)
        if not match: raise ValueError(f'Invalid image: {s}')
        imgpath=(source.parent/match.group(2)).resolve()
        if imgpath.stem in DIAGRAMS and 'figures/v08/' in match.group(2):
            story.extend([Spacer(1,4),DIAGRAMS[imgpath.stem],Spacer(1,10)]);i+=1;continue
        iw,ih=Image.open(imgpath).size
        # Use the small cover illustration once; diagrams fill the text column.
        width=WIDTH
        image_block=RLImage(str(imgpath),width=width,height=width*ih/iw)
        image_block.hAlign='CENTER'
        story.extend([Spacer(1,3),image_block,Spacer(1,7)]);i+=1;continue
    if s.startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].strip().startswith('|'):
            cells=[x.strip() for x in lines[i].strip().strip('|').split('|')]
            if not all(re.fullmatch(r':?-+:?',x) for x in cells): rows.append(cells)
            i+=1
        n=len(rows[0]);widths=[112,WIDTH-112] if n==2 else [90,174,WIDTH-264] if n==3 else [WIDTH/n]*n
        # Schedule needs a narrow time column.
        if rows[0][0]=='时段': widths=[63,216,WIDTH-279]
        if rows[0][0]=='内容': widths=[123,192,WIDTH-315]
        content=[[Paragraph(rich(x),styles['headcell' if ri==0 else 'cell']) for x in row] for ri,row in enumerate(rows)]
        t=Table(content,colWidths=widths,hAlign='LEFT',repeatRows=1)
        t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),PALE),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),('LINEBELOW',(0,0),(-1,0),.7,LINE),('LINEBELOW',(0,1),(-1,-1),.35,LINE)]))
        story.extend([t,Spacer(1,9)]);continue
    if s.startswith('# '):
        story.append(Paragraph(rich(s[2:]),styles['title']));i+=1;continue
    if s.startswith('## '):
        story.append(Paragraph(rich(s[3:]),styles['h2']));i+=1;continue
    if s.startswith('### '):
        story.append(Paragraph(rich(s[4:]),styles['h3']));i+=1;continue
    if s.startswith('- '):
        story.append(Paragraph('· '+rich(s[2:]),styles['bullet']));i+=1;continue
    if re.match(r'^\d+\. ',s):
        story.append(Paragraph(rich(s),styles['body']));i+=1;continue
    caption=s.startswith(('图示为','示意采用','例子按','这些是','方案依据','AI PLAY 72H 预赛'))
    story.append(Paragraph(rich(s),styles['caption' if caption else 'body']));i+=1
pdf=OUT/'AI_PLAY_72H_预赛方案_精炼特色版_v0.8.pdf'
doc=SimpleDocTemplate(str(pdf),pagesize=(595.28,841.89),rightMargin=44,leftMargin=44,topMargin=37,bottomMargin=54,title='请本人到场 - AI PLAY 72H 预赛方案 精炼特色版',author='nekoToken',subject='实时潜入、个人Agent协作与双重RESET')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
reader=PdfReader(str(pdf))
texts=[p.extract_text() or '' for p in reader.pages]
(TMP/'extracted_text.txt').write_text('\n\n'.join(texts),encoding='utf-8')
report={'pdf':str(pdf),'pages':len(reader.pages),'page_char_counts':[len(t) for t in texts],'figures':['roles','coop','loop','reset'],'illustration':str(ROOT/'output/imagegen/请本人到场_检查区_名称标注_v6.png'),'source':str(source)}
(TMP/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
logging.info(json.dumps(report,ensure_ascii=False))
