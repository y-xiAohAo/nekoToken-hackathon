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
FIG = OUT / 'figures/v04'
TMP = ROOT / 'tmp/pdfs/preliminary_v04'
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

loop=Drawing(WIDTH,249)
node(loop,8,8,145,44,'实时行动与感知','移动 / 维修；设备持续观察','teal')
node(loop,181,8,145,44,'定时批量上报','记录观察时刻与区域')
node(loop,354,8,145,44,'周期结束，暂停定位','城市系统判断当前位置','warm')
arrow(loop,[(153,30),(181,30)])
arrow(loop,[(326,30),(354,30)])
node(loop,354,82,145,37,'程序检查是否命中')
arrow(loop,[(426,52),(426,82)])
node(loop,181,83,145,42,'未命中：城市系统调度','可新增一处设施','warm')
arrow(loop,[(354,101),(326,101)])
arrow(loop,[(181,104),(166,104),(166,1),(80,1),(80,8)])
node(loop,354,151,145,42,'命中：是否使用回退？','次数不足则本轮失败')
arrow(loop,[(426,119),(426,151)])
node(loop,181,151,145,42,'使用：恢复周期起点','消耗1次玩家回退','teal')
arrow(loop,[(354,172),(326,172)])
arrow(loop,[(181,172),(166,172),(166,104)])
node(loop,354,218,145,26,'放弃 / 用尽：本轮失败')
arrow(loop,[(426,193),(426,218)])
node(loop,8,151,145,42,'修好电机并抵达出口','本轮成功','teal')
arrow(loop,[(80,52),(80,151)])
add_text(loop,168,233,'回退与系统调度分别处理',8.2,color=MUTED)
save_diagram('loop',loop)

contact=Drawing(WIDTH,104)
boxes=[(0,116,'到达并开始联络','暂停全部游戏计时'),(130,116,'玩家描述，助手比较','无地图，缺信息先追问'),(260,116,'结束会话并提交','每次最多1–2个改动'),(390,117,'恢复实时行动','玩家观察变化并手操')]
for x,w,title,sub in boxes:
    node(contact,x,10,w,50,title,sub,'teal')
for x in (116,246,376):
    arrow(contact,[(x,35),(x+14,35)],TEAL)
add_text(contact,WIDTH/2,86,'各联络点每轮一次；局部回退按起点记录恢复使用状态',9.2,color=MUTED)
save_diagram('contact',contact)

reset=Drawing(WIDTH,204)
for i in range(4):
    x=3+i*131
    node(reset,x,13,108,45,f'第{i+1}轮','通关或最终失败')
    if i<3:
        arrow(reset,[(x+108,35),(x+131,35)],TEAL)
        add_text(reset,x+119,75,'重启',8.1,color=TEAL)
add_text(reset,WIDTH/2,98,'初始轮 + 城市系统重启3次，共4轮',10,True)
node(reset,3,125,151,43,'定位命中','玩家选择局部回退','warm')
node(reset,180,125,151,43,'消耗1次玩家回退','整场共享3次，不补满')
node(reset,357,125,147,43,'恢复本周期起点','设备与联络状态一并恢复','teal')
arrow(reset,[(154,146),(180,146)])
arrow(reset,[(331,146),(357,146)])
add_text(reset,WIDTH/2,195,'各自记忆保留；玩家剩余回退次数和已结算成绩不恢复',9.2,color=MUTED)
save_diagram('reset',reset)

label_path=ROOT/'output/imagegen/请本人到场_检查区_名称标注_v6.png'

styles={
 'title':ParagraphStyle('title',fontName='YHB',fontSize=28,leading=36,textColor=INK,spaceAfter=8),
 'h2':ParagraphStyle('h2',fontName='YHB',fontSize=15,leading=21,textColor=TEAL,spaceBefore=10,spaceAfter=10,wordWrap='CJK',keepWithNext=True),
 'h3':ParagraphStyle('h3',fontName='YHB',fontSize=11.5,leading=17,textColor=INK,spaceBefore=10,spaceAfter=7,wordWrap='CJK',keepWithNext=True),
 'body':ParagraphStyle('body',fontName='YH',fontSize=9.5,leading=15,textColor=INK,spaceAfter=7,wordWrap='CJK'),
 'caption':ParagraphStyle('caption',fontName='YH',fontSize=8,leading=12,textColor=MUTED,spaceAfter=8,wordWrap='CJK'),
 'cell':ParagraphStyle('cell',fontName='YH',fontSize=8.6,leading=13,textColor=INK,wordWrap='CJK'),
 'headcell':ParagraphStyle('headcell',fontName='YHB',fontSize=8.6,leading=13,textColor=INK,wordWrap='CJK'),
 'bullet':ParagraphStyle('bullet',fontName='YH',fontSize=9.5,leading=15,textColor=INK,spaceAfter=6,leftIndent=12,firstLineIndent=-9,wordWrap='CJK'),
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
    canvas.drawString(44,28,'nekoToken  /  请本人到场  /  预赛方案 v0.4 · 自检修订稿')
    canvas.drawRightString(551,28,str(doc.page))
    canvas.restoreState()

source=OUT/'AI_PLAY_72H_预赛方案_v0.4.md'
lines=source.read_text(encoding='utf-8').splitlines()
story=[];i=0
while i<len(lines):
    s=lines[i].strip()
    if not s:
        i+=1;continue
    if s=='<!-- page-break -->':
        story.append(PageBreak());i+=1;continue
    if s.startswith('!['):
        match=re.fullmatch(r'!\[(.*?)\]\((.*?)\)',s)
        if not match: raise ValueError(f'Invalid image: {s}')
        imgpath=(source.parent/match.group(2)).resolve()
        iw,ih=Image.open(imgpath).size
        # Keep the cover illustration and its caption on page one; later map art uses full text width.
        width=WIDTH if 'figures/' in match.group(2) else (WIDTH if len([x for x in story if isinstance(x,PageBreak)])>0 else 280)
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
pdf=OUT/'AI_PLAY_72H_预赛方案_v0.4.pdf'
doc=SimpleDocTemplate(str(pdf),pagesize=(595.28,841.89),rightMargin=44,leftMargin=44,topMargin=37,bottomMargin=54,title='请本人到场 - AI PLAY 72H 预赛方案',author='nekoToken',subject='实时潜入、个人Agent协作与双重RESET')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
reader=PdfReader(str(pdf))
texts=[p.extract_text() or '' for p in reader.pages]
(TMP/'extracted_text.txt').write_text('\n\n'.join(texts),encoding='utf-8')
report={'pdf':str(pdf),'pages':len(reader.pages),'page_char_counts':[len(t) for t in texts],'figures':['loop','contact','reset'],'illustration':str(label_path),'source':str(source)}
(TMP/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
logging.info(json.dumps(report,ensure_ascii=False))
