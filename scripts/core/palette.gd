class_name Palette
extends RefCounted
## Единая палитра игры. Все цвета — HDR-совместимые (значения могут быть > 1.0,
## благодаря rendering/viewport/hdr_2d=true они дают мягкое свечение).

const BG_DEEP := Color(0.02, 0.04, 0.09)
const BG_MID := Color(0.04, 0.10, 0.17)

const TEXT := Color(0.91, 0.96, 1.0)
const TEXT_DIM := Color(0.54, 0.65, 0.76)
const TEXT_FAINT := Color(0.36, 0.45, 0.55)

const CYAN := Color(0.45, 0.94, 0.85)
const AQUA := Color(0.35, 0.79, 1.0)
const GOLD := Color(1.0, 0.85, 0.63)
const PINK := Color(1.0, 0.62, 0.81)
const VIOLET := Color(0.72, 0.62, 1.0)
const GREEN := Color(0.62, 1.0, 0.69)

const CARD_BG := Color(0.05, 0.10, 0.16, 0.74)
const CARD_BG_HOVER := Color(0.08, 0.16, 0.24, 0.86)
const CARD_BORDER := Color(0.55, 0.85, 1.0, 0.12)
const PANEL_BG := Color(0.03, 0.07, 0.12, 0.82)

const DANGER := Color(1.0, 0.45, 0.45)

## Мягкое свечение цвета: возвращает цвет с усиленной яркостью.
static func glow(c: Color, strength: float = 1.6) -> Color:
	return Color(c.r * strength, c.g * strength, c.b * strength, c.a)


## Полупрозрачный вариант цвета.
static func fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
