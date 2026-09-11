// The panel's position is intent; only its rendered position is clamped.
import type { PanelPos } from '../utils/playground-store.ts';

export const PANEL_WIDTH = 312;
export const DRAG_THRESHOLD = 4;
export interface Size { width: number; height: number }

export function defaultPos(region: Size): PanelPos {
  return { x: region.width - 16 - PANEL_WIDTH, y: 52 };
}

export function clampPanel(pos: PanelPos, size: Size, region: Size): PanelPos {
  return {
    x: Math.max(0, Math.min(pos.x, region.width - size.width)),
    y: Math.max(0, Math.min(pos.y, region.height - size.height)),
  };
}

export function positionFromDrag(start: PanelPos, from: PanelPos, to: PanelPos): PanelPos {
  return { x: start.x + to.x - from.x, y: start.y + to.y - from.y };
}

export function crossedThreshold(from: PanelPos, to: PanelPos): boolean {
  return Math.max(Math.abs(to.x - from.x), Math.abs(to.y - from.y)) >= DRAG_THRESHOLD;
}
