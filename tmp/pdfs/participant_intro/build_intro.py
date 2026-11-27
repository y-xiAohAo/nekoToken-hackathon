"""Create a one-page AI PLAY participant introduction from verified resume facts."""

from __future__ import annotations

import logging
from pathlib import Path
from xml.sax.saxutils import escape

from pypdf import PdfReader
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph


ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'PRELIMINARY_DESIGN_SPEC.md').is_file())
TMP = ROOT / "tmp/pdfs/participant_intro"
OUTPUT = ROOT / "output/pdf/董骏豪_AI_PLAY_参赛者介绍_v1.pdf"
SOURCE_PDF = ROOT / "source_materials/resume/董骏豪的简历.pdf"
INK = colors.HexColor("#23343D")
MUTED = colors.HexColor("#60717B")
TEAL = colors.HexColor("#196F6A")
RULE = colors.HexColor("#D6E2E1")
PALE = colors.HexColor("#EFF6F5")
PAGE_W, PAGE_H = A4
MARGIN = 40.0
WIDTH = PAGE_W - 2 * MARGIN


def paragraph(
    pdf: canvas.Canvas,
    text: str,
    x: float,
    top: float,
    width: float = WIDTH,
    size: float = 10.5,
    leading: float = 16.0,
    color: colors.Color = INK,
    bold: bool = False,
) -> float:
    """Draw a wrapping paragraph and return the next available top position."""
    style = ParagraphStyle(
        "body",
        fontName="IntroBold" if bold else "IntroRegular",
        fontSize=size,
        leading=leading,
        textColor=color,
        wordWrap="CJK",
        alignment=TA_LEFT,
        splitLongWords=False,
        allowWidows=0,
        allowOrphans=0,
    )
    block = Paragraph(text, style)
    _, height = block.wrap(width, PAGE_H)
    block.drawOn(pdf, x, top - height)
    return top - height


def heading(pdf: canvas.Canvas, title: str, top: float) -> float:
    """Draw a section heading with a quiet horizontal rule."""
    bottom = paragraph(pdf, title, MARGIN, top, size=12.2, leading=18, bold=True)
    line_x = MARGIN + pdfmetrics.stringWidth(title, "IntroBold", 12.2) + 13
    pdf.setStrokeColor(RULE)
    pdf.setLineWidth(0.6)
    pdf.line(line_x, top - 10, PAGE_W - MARGIN, top - 10)
    return bottom - 9


def bullet(pdf: canvas.Canvas, text: str, top: float) -> float:
    """Draw a plain bullet with a hanging indent."""
    pdf.setFillColor(TEAL)
    pdf.circle(MARGIN + 2.5, top - 7.0, 1.6, fill=1, stroke=0)
    return paragraph(pdf, text, MARGIN + 12, top, width=WIDTH - 12) - 4


def project(
    pdf: canvas.Canvas, title: str, description: str, url: str, points: list[str], top: float
) -> float:
    """Render a project name, a readable repository link, and two concise bullets."""
    top = paragraph(
        pdf,
        f'<font name="IntroBold">{escape(title)}</font>'
        f' <font color="#60717B">｜{escape(description)}</font>',
        MARGIN,
        top,
        size=11.1,
        leading=17,
    ) - 3
    label = url.removeprefix("https://")
    top = paragraph(
        pdf,
        f'<link href="{url}" color="#196F6A">{label}</link>',
        MARGIN,
        top,
        size=9.1,
        leading=13,
    ) - 6
    for point in points:
        top = bullet(pdf, point, top)
    return top - 9


def build() -> None:
    """Generate the final PDF, preserving all source documents."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    pdfmetrics.registerFont(TTFont("IntroRegular", "C:/Windows/Fonts/msyh.ttc", subfontIndex=0))
    pdfmetrics.registerFont(TTFont("IntroBold", "C:/Windows/Fonts/msyhbd.ttc", subfontIndex=0))
    pdfmetrics.registerFontFamily("IntroRegular", normal="IntroRegular", bold="IntroBold")
    TMP.mkdir(parents=True, exist_ok=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    portrait = TMP / "portrait.png"
    source = PdfReader(SOURCE_PDF)
    source.pages[0].images[0].image.save(portrait)

    pdf = canvas.Canvas(str(OUTPUT), pagesize=A4, pageCompression=1)
    pdf.setTitle("董骏豪 | AI PLAY 参赛者介绍")
    pdf.setAuthor("董骏豪")
    pdf.setSubject("nekoToken 团队成员介绍：Agent 项目、协作能力与参赛方向")

    top = PAGE_H - 35
    paragraph(pdf, "AI PLAY  /  参赛者介绍", MARGIN, top, size=9.2, leading=14, color=TEAL, bold=True)
    paragraph(pdf, "董骏豪", MARGIN, top - 27, size=29, leading=38, bold=True)
    paragraph(pdf, "nekoToken  ·  Agent 开发 / 工具接入 / AI 辅助编程", MARGIN, top - 75,
              width=WIDTH - 80, size=10, leading=15, color=MUTED)
    paragraph(pdf,
              '<link href="tel:13479295221">134-7929-5221</link>'
              '  ·  <link href="mailto:202420111252@mail.scut.edu.cn">202420111252@mail.scut.edu.cn</link>',
              MARGIN, top - 97, size=9.3, leading=14, color=INK)
    paragraph(pdf, '<link href="https://github.com/y-xiAohAo" color="#196F6A">github.com/y-xiAohAo</link>',
              MARGIN, top - 113, size=9.3, leading=14)
    photo_w = 63.0
    photo_h = photo_w * 420 / 360
    pdf.drawImage(str(portrait), PAGE_W - MARGIN - photo_w, top - photo_h - 8,
                  width=photo_w, height=photo_h, mask="auto")
    pdf.setStrokeColor(TEAL)
    pdf.setLineWidth(1.3)
    pdf.line(MARGIN, top - 139, PAGE_W - MARGIN, top - 139)

    top -= 153
    top = paragraph(
        pdf,
        "我是华南理工大学信息与通信工程专业的硕士生。近期主要在做能调用工具、执行任务、"
        "保留记忆的 Agent，做过代码沙箱和科研仿真方向的项目。这次想把这些经验放进游戏里，"
        "探索人和 Agent 协作的玩法。",
        MARGIN, top, size=10.6, leading=16.5,
    ) - 17

    top = heading(pdf, "做过的项目", top)
    top = project(pdf, "Litmus Agent", "自我纠错的编程 Agent",
                  "https://github.com/y-xiAohAo/litmusAgent", [
                      "自研 Agent 框架，串起任务拆解、沙箱执行和报错后的修正，并让任务信息跨会话保留。",
                      "接入 MCP 工具，处理工作区与执行权限；自建 125 个代码生成、执行和纠错任务，"
                      "用真实模型运行检查机制是否有效。",
                  ], top)
    top = project(pdf, "TMS Research Agent", "科研仿真自动化",
                  "https://github.com/y-xiAohAo/TMSresearch-agent", [
                      "把论文检索、参数提取、建模和结果核对串成工作流，通过 18 个工具驱动仿真软件。",
                      "为提取参数保留原文证据、做结构校验，并记录工具调用和失败原因，便于检查结果、定位问题。",
                  ], top)

    top = heading(pdf, "能力与协作", top + 1)
    for label, content in [
        ("Agent 接入", "熟悉 Python、LangGraph、Function Calling 和 MCP，"
                       "有工具编排、跨会话记忆与错误恢复实践。"),
        ("开发与验证", "常用 Codex、Claude Code，习惯先写清规则与接口，再迭代实现，用测试检查关键行为。"),
        ("工程支持", "用过 Docker、FastAPI、SQLAlchemy、Redis，"
                     "希望在团队里承担 Agent 接入、状态记录与调试相关工作。"),
    ]:
        top = paragraph(pdf, f'<font name="IntroBold">{label}</font>　{content}',
                        MARGIN, top, size=10.2, leading=15.5) - 4
    top -= 10

    box_top = top
    box_content_top = box_top - 12
    title = "这次想尝试：《请本人到场》"
    state = "当前处于方案设计阶段，计划使用 Godot。"
    game = ("玩家负责潜入观察，通过对话让个人 Agent 调整设备；系统 Agent 根据设备报告推断位置。"
            "RESET 后双方保留各自记忆。希望在 72 小时内验证：双方信息和工具权限受限时，"
            "玩家与 Agent 能否通过沟通共同完成任务。")
    # Measure the card before drawing its background.
    measure_style = ParagraphStyle("measure", fontName="IntroRegular", fontSize=10.2,
                                   leading=15.5, wordWrap="CJK")
    game_height = Paragraph(game, measure_style).wrap(WIDTH - 28, PAGE_H)[1]
    box_height = 12 + 18 + 4 + 13.5 + 7 + game_height + 12
    pdf.setFillColor(PALE)
    pdf.roundRect(MARGIN, box_top - box_height, WIDTH, box_height, 5, fill=1, stroke=0)
    box_content_top = paragraph(pdf, title, MARGIN + 14, box_content_top, width=WIDTH - 28,
                                size=11.3, leading=18, color=TEAL, bold=True) - 4
    box_content_top = paragraph(pdf, state, MARGIN + 14, box_content_top, width=WIDTH - 28,
                                size=9, leading=13.5, color=MUTED) - 7
    paragraph(pdf, game, MARGIN + 14, box_content_top, width=WIDTH - 28, size=10.2, leading=15.5)
    top = box_top - box_height - 16

    top = heading(pdf, "教育与实习", top)
    for line in [
        '<font name="IntroBold">华南理工大学</font>　信息与通信工程硕士　'
        '<font color="#60717B">2024.09 - 2027.06（预计）</font>',
        '<font name="IntroBold">湖南大学</font>　通信工程本科　'
        '<font color="#60717B">2020.09 - 2024.06</font>',
        '<font name="IntroBold">阿里巴巴国际 · Lazada</font>　AI 选品 Agent 研发实习生　'
        '<font color="#60717B">2026.05 - 2026.08</font>',
    ]:
        top = paragraph(pdf, line, MARGIN, top, size=9.4, leading=15) - 2
    top = paragraph(pdf, "实习期间做过 LangGraph 工作流、Agent 工具与 CLI，以及调用链评测。",
                    MARGIN, top - 1, size=9.3, leading=14, color=MUTED)

    if top < 34:
        raise ValueError(f"Page content would overflow: final baseline {top:.1f}")
    pdf.showPage()
    pdf.save()
    reader = PdfReader(OUTPUT)
    if len(reader.pages) != 1:
        raise ValueError("Participant introduction must occupy exactly one page")
    logging.info("Created %s; one page; final text bottom %.1f pt", OUTPUT, top)


if __name__ == "__main__":
    build()
