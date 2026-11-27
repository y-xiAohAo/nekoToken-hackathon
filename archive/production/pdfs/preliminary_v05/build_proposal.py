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
FIG = OUT / 'figures/v05'
TMP = ROOT / 'tmp/pdfs/preliminary_v05'
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

def add_text(d: Drawing, x: float, top: float, value: str, size: float = 10, bold: bool = False, color: Color = INK, anchor: str = 'middle') -> None:
    d.add(String(x, d.height-top, value, fontName='YHB' if bold else 'YH', fontSize=size, fillColor=color, textAnchor=anchor))

def node(d: Drawing, x: float, y: float, w: float, h: float, title: str, sub: str = '', tone: str = 'plain') -> None:
    fill = PALE if tone == 'teal' else AMBER if tone == 'warm' else GRAY
    d.add(Rect(x, d.height-y-h, w, h, rx=4, ry=4, fillColor=fill, strokeColor=LINE, strokeWidth=.65))
    add_text(d, x+w/2, y+(h/2-3 if sub else h/2+3), title, 10.1, True)
    if sub:
        add_text(d, x+w/2, y+h/2+11, sub, 8.2, color=MUTED)

def arrow(d: Drawing, points: list[tuple[float, float]], color: Color = MUTED) -> None:
    flat = [z for x,y in points for z in (x,d.height-y)]
    d.add(PolyLine(flat, strokeColor=color, strokeWidth=.85, fillColor=None))
    x,y = points[-1]; px,py=points[-2]
    a=math.atan2(y-py,x-px); r=4
    tip=[x,d.height-y, x-r*math.cos(a-.48),d.height-(y-r*math.sin(a-.48)), x-r*math.cos(a+.48),d.height-(y-r*math.sin(a+.48))]
    d.add(Polygon(tip,fillColor=color,strokeColor=color,strokeWidth=.3))

def save_diagram(name: str, d: Drawing) -> None:
    renderPDF.drawToFile(d,str(TMP / f'{name}.pdf'))
    renderSVG.drawToFile(d,str(FIG / f'{name}.svg'))
    subprocess.run(['pdftoppm','-png','-singlefile','-r','220',str(TMP / f'{name}.pdf'),str(FIG / name)],check=True,capture_output=True)

coop=Drawing(WIDTH,95)
for x,title,sub in [(0,'玩家观察与描述','设备 / 路线 / 意图'),(132,'助手追问与比较','无地图，依据玩家描述'),(264,'接口提交，程序校验','每次最多1-2个改动'),(396,'现场变化，玩家行动','离点后继续观察')]:
    node(coop,x,10,111,50,title,sub,'teal')
for x in (111,243,375):
    arrow(coop,[(x,35),(x+21,35)],TEAL)
add_text(coop,WIDTH/2,84,'联络时暂停全部游戏计时；会话结束后生效',9,color=MUTED)
save_diagram('coop',coop)

reset=Drawing(WIDTH,140)
add_text(reset,3,13,'玩家：定位命中后，可局部回退',10,True,anchor='start')
node(reset,3,28,147,40,'命中后选择回退','整场共享3次','warm')
node(reset,180,28,147,40,'恢复周期起点','消耗1次，不补回','teal')
node(reset,357,28,147,40,'带着经历再行动','各自记忆保留')
arrow(reset,[(150,48),(180,48)],TEAL)
arrow(reset,[(327,48),(357,48)],TEAL)
add_text(reset,3,88,'城市系统：初始轮 + 3次整轮重启，共4轮',10,True,anchor='start')
for i in range(4):
    x=3+i*132
    node(reset,x,100,108,34,f'第{i+1}轮')
    if i<3:
        arrow(reset,[(x+108,117),(x+132,117)],TEAL)
save_diagram('reset',reset)

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
    canvas.drawString(44,28,'nekoToken  /  请本人到场  /  精炼特色版 v0.5 · 2026.11.16')
    canvas.drawRightString(551,28,str(doc.page))
    canvas.restoreState()

source=OUT/'AI_PLAY_72H_预赛方案_精炼特色版_v0.5.md'
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
        iw,ih=Image.open(imgpath).size
        # Use the small cover illustration once; diagrams fill the text column.
        width=WIDTH if 'figures/' in match.group(2) else 275
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
pdf=OUT/'AI_PLAY_72H_预赛方案_精炼特色版_v0.5.pdf'
doc=SimpleDocTemplate(str(pdf),pagesize=(595.28,841.89),rightMargin=44,leftMargin=44,topMargin=37,bottomMargin=54,title='请本人到场 - AI PLAY 72H 预赛方案 精炼特色版',author='nekoToken',subject='实时潜入、个人Agent协作与双重RESET')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
reader=PdfReader(str(pdf))
texts=[p.extract_text() or '' for p in reader.pages]
(TMP/'extracted_text.txt').write_text('\n\n'.join(texts),encoding='utf-8')
report={'pdf':str(pdf),'pages':len(reader.pages),'page_char_counts':[len(t) for t in texts],'figures':['coop','reset'],'illustration':str(ROOT/'output/imagegen/请本人到场_大地图_v5_clean.png'),'source':str(source)}
(TMP/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
logging.info(json.dumps(report,ensure_ascii=False))
