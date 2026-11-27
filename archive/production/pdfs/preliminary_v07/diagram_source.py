"""Draw clear vector flowcharts in the game's cyber interface palette."""
from __future__ import annotations

import math
from pathlib import Path

from reportlab.graphics import renderPDF, renderSVG
from reportlab.graphics.shapes import Drawing, Line, Polygon, PolyLine, Rect, String
from reportlab.lib.colors import Color, HexColor
from reportlab.pdfbase import pdfmetrics

WIDTH = 507.28
BG = HexColor('#0C1724')
GRID = HexColor('#162838')
PANEL = HexColor('#142536')
WHITE = HexColor('#ECF5FA')
MUTED = HexColor('#AFBDCB')
PLAYER = HexColor('#5AE0D3')
ASSISTANT = HexColor('#8CB5FF')
CITY = HexColor('#FFBE69')
ENGINE = HexColor('#D6E4EB')
FAIL = HexColor('#FFA0AA')


def write(d: Drawing, x: float, top: float, value: str, size: float = 10,
          color: Color = WHITE, bold: bool = False, anchor: str = 'start',
          max_width: float | None = None) -> None:
    """Place Chinese text using top-origin positions and measured fitting."""
    face = 'YHB' if bold else 'YH'
    if max_width is not None:
        while pdfmetrics.stringWidth(value, face, size) > max_width and size > 8:
            size -= .2
    d.add(String(x, d.height-top, value, fontName=face, fontSize=size,
                 fillColor=color, textAnchor=anchor))


def frame(height: float, title: str, state: str) -> Drawing:
    """Create a restrained dark panel with grid and readable state labels."""
    d = Drawing(WIDTH, height)
    d.add(Rect(0, 0, WIDTH, height, fillColor=BG, strokeColor=BG))
    for x in range(12, 508, 24):
        d.add(Line(x, 0, x, height, strokeColor=GRID, strokeWidth=.22))
    for y in range(12, int(height), 24):
        d.add(Line(0, y, WIDTH, y, strokeColor=GRID, strokeWidth=.22))
    d.add(Rect(0, height-3, 54, 3, fillColor=PLAYER, strokeColor=PLAYER))
    d.add(Line(16, height-36, WIDTH-16, height-36, strokeColor=GRID, strokeWidth=.8))
    write(d, 16, 23, title, 12.3, bold=True)
    write(d, WIDTH-16, 23, state, 8.2, MUTED, anchor='end')
    return d


def cell(d: Drawing, x: float, top: float, width: float, height: float,
         title: str, sub: str, color: Color, tag: str = '') -> None:
    """Create a cut-corner panel with role, action, and supporting detail."""
    notch = 7
    points = [x, d.height-top, x+width-notch, d.height-top,
              x+width, d.height-top-notch, x+width, d.height-top-height,
              x+notch, d.height-top-height, x, d.height-top-height+notch]
    d.add(Polygon(points, fillColor=PANEL, strokeColor=color, strokeWidth=.65))
    d.add(Rect(x, d.height-top-height+8, 2, height-16, fillColor=color, strokeColor=color))
    if tag:
        write(d, x+10, top+17, tag, 8.1, color, max_width=width-18)
        title_top = top+35
    else:
        title_top = top+height/2-3 if sub else top+height/2+3
    write(d, x+10, title_top, title, 10.3, WHITE, True, max_width=width-20)
    if sub:
        write(d, x+10, title_top+16, sub, 8.2, MUTED, max_width=width-20)


def edge(d: Drawing, points: list[tuple[float, float]], color: Color = ENGINE) -> None:
    """Draw one unambiguous orthogonal flow edge and arrowhead."""
    flat = [v for x, y in points for v in (x, d.height-y)]
    d.add(PolyLine(flat, strokeColor=color, strokeWidth=1, fillColor=None))
    x, y = points[-1]
    px, py = points[-2]
    angle = math.atan2(y-py, x-px)
    radius = 4.3
    arrow = [x, d.height-y,
             x-radius*math.cos(angle-.46), d.height-(y-radius*math.sin(angle-.46)),
             x-radius*math.cos(angle+.46), d.height-(y-radius*math.sin(angle+.46))]
    d.add(Polygon(arrow, fillColor=color, strokeColor=color, strokeWidth=.3))


def build_diagrams() -> dict[str, Drawing]:
    """Return the role overview, cooperation, localization, and reset diagrams."""
    roles = frame(128, '三方分工', '')
    cell(roles, 16, 48, 147, 66, '观察、移动、维修', '在联络点与助手讨论', PLAYER, '玩家')
    cell(roles, 180, 48, 147, 66, '讨论对策、改动设备', '看不到地图和画面', ASSISTANT, '个人助手')
    cell(roles, 344, 48, 147, 66, '定位、调度设备', '靠设备报告判断位置', CITY, '城市系统')

    coop = frame(258, '与助手联络', '交谈时暂停游戏')
    cell(coop, 16, 60, 147, 66, '说明现场和打算', '设备位置、准备走的路线', PLAYER, '玩家')
    cell(coop, 180, 60, 147, 66, '追问、讨论对策', '', ASSISTANT, '个人助手')
    cell(coop, 344, 60, 147, 66, '选定改动', '灯或摄像头，最多1-2项', ASSISTANT, '个人助手')
    edge(coop, [(163, 87), (180, 87)], PLAYER)
    edge(coop, [(180, 110), (163, 110)], ASSISTANT)
    edge(coop, [(327, 93), (344, 93)], ASSISTANT)
    edge(coop, [(417, 126), (417, 162)], ASSISTANT)
    write(coop, 430, 147, '结束会话', 8.2, ASSISTANT)
    cell(coop, 344, 162, 147, 66, '提交指令', '', ASSISTANT, '个人助手')
    cell(coop, 180, 162, 147, 66, '检查并执行改动', '', ENGINE, '游戏程序')
    cell(coop, 16, 162, 147, 66, '继续潜入', '', PLAYER, '玩家')
    edge(coop, [(344, 195), (327, 195)], ENGINE)
    edge(coop, [(180, 195), (163, 195)], PLAYER)
    write(coop, 16, 246, '每个联络点每轮可用一次。', 8.5, MUTED)

    loop = frame(432, '周期定位', '')
    cell(loop, 16, 56, 147, 66, '移动、维修', '设备持续观察', PLAYER, '玩家')
    cell(loop, 180, 56, 147, 66, '定时上报', '时间、区域、观察结果', ENGINE, '设备')
    cell(loop, 344, 56, 147, 66, '暂停游戏', '收到固定批次后', ENGINE, '游戏程序')
    edge(loop, [(163, 89), (180, 89)], ENGINE)
    edge(loop, [(327, 89), (344, 89)], CITY)
    edge(loop, [(417, 122), (417, 146)], CITY)
    cell(loop, 344, 146, 147, 66, '推测玩家所在区域', '形状固定、大小受限', CITY, '城市系统')
    cell(loop, 180, 146, 147, 66, '核对当前位置', '', ENGINE, '游戏程序')
    cell(loop, 16, 146, 147, 66, '城市系统调整设备', '可新增1处设施', CITY, '未命中')
    edge(loop, [(344, 179), (327, 179)], ENGINE)
    edge(loop, [(180, 179), (163, 179)], CITY)
    edge(loop, [(89, 146), (89, 122)], CITY)
    write(loop, 101, 137, '恢复行动', 8.2, CITY)
    edge(loop, [(253, 212), (253, 238)], FAIL)
    write(loop, 266, 230, '命中', 8.6, FAIL)
    cell(loop, 180, 238, 147, 62, '是否回退？', '', PLAYER, '玩家')
    edge(loop, [(253, 300), (253, 313), (89, 313), (89, 332)], PLAYER)
    edge(loop, [(253, 313), (417, 313), (417, 332)], FAIL)
    write(loop, 118, 325, '回退', 8.5, PLAYER)
    write(loop, 338, 325, '放弃或次数用尽', 8.5, FAIL)
    cell(loop, 16, 332, 147, 62, '回到本周期起点', '消耗1次回退', PLAYER)
    cell(loop, 344, 332, 147, 62, '本轮失败', '继续剩余轮次', FAIL)
    edge(loop, [(16, 363), (7, 363), (7, 89), (16, 89)], PLAYER)
    write(loop, 16, 418, '修好电机并抵达出口，即本轮成功。', 8.5, MUTED)

    reset = frame(280, '回退与重启', '各方记忆保留')
    write(reset, 16, 50, '玩家回退', 10, PLAYER, True)
    write(reset, 491, 50, '整场共3次', 8.4, MUTED, anchor='end')
    cell(reset, 16, 63, 140, 62, '定位命中', '玩家选择回退', PLAYER)
    cell(reset, 184, 63, 140, 62, '恢复周期起点', '', ENGINE)
    cell(reset, 352, 63, 140, 62, '继续行动', '到可用联络点才能交谈', PLAYER)
    edge(reset, [(156, 94), (184, 94)], ENGINE)
    edge(reset, [(324, 94), (352, 94)], PLAYER)
    reset.add(Rect(16, reset.height-169, 475, 29, fillColor=PANEL, strokeColor=GRID))
    write(reset, 24, 158, '现场和联络点按起点状态恢复，回退次数不补回。', 8.7, MUTED)
    write(reset, 16, 194, '城市系统重启', 10, CITY, True)
    write(reset, 491, 194, '初始轮加3次重启，共4轮', 8.5, MUTED, anchor='end')
    for index in range(4):
        x = 16+index*125
        cell(reset, x, 207, 100, 42, f'第{index+1}轮', '', CITY)
        if index < 3:
            edge(reset, [(x+100, 228), (x+125, 228)], CITY)
    write(reset, 16, 269, '重启时重新配置设备，维修重来，联络点恢复可用。', 8.5, MUTED)
    return {'roles': roles, 'coop': coop, 'loop': loop, 'reset': reset}


def save_vectors(diagrams: dict[str, Drawing], folder: Path) -> None:
    """Export standalone SVGs and vector PDFs for editing and reuse."""
    folder.mkdir(parents=True, exist_ok=True)
    for name, drawing in diagrams.items():
        renderSVG.drawToFile(drawing, str(folder/f'{name}.svg'))
        renderPDF.drawToFile(drawing, str(folder/f'{name}.pdf'))
