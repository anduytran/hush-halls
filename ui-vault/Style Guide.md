---
tags: [ui, style]
---
# Style Guide

> Fill this in (or ask the UI Builder to draft it from the existing UI). Agents follow it.

## Colours
| Name | Hex | Used for |
| --- | --- | --- |
| Background | #0F1115 | Panels |
| Accent | #F5A524 | Primary buttons, highlights |
| Text | #E8EAF1 | Body text |
| Danger | #FF6B6B | Warnings, damage |
| Water | #3A8DFF | Water bar fill, title card tagline and edge/glow strokes |

## Typography
- Headings: BuilderSans Bold
- Body: BuilderSans Medium
- Minimum text size: 14 on phone screens

## Sizing and layout
- Size with Scale (UDim2) plus UISizeConstraint/UITextSizeConstraint, not fixed pixels
- Spacing steps: 4 · 8 · 12 · 16 · 24 (UIPadding, UIListLayout.Padding)
- Respect the top bar inset and phone safe areas; keep touch targets large enough to tap
- Layouts: UIListLayout / UIGridLayout; corners: UICorner 8

## Motion
- TweenService, 0.15–0.25 s, Quad Out for UI transitions

## Accessibility
- Don't rely on colour alone; keep strong contrast between text and background
