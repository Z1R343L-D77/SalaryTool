import { describe, expect, it } from "vitest";
import {
  FONT_SCALE_VALUES,
  createDefaultSettings,
  normalizeSettings,
} from "./settings";

describe("外观设置", () => {
  it("默认值：跟随系统、标准字号、富士山壁纸、不透明效果关闭", () => {
    expect(createDefaultSettings()).toEqual({
      theme: "system",
      fontScale: "md",
      wallpaper: "fuji",
      reduceTransparency: false,
    });
  });

  it("缺失字段用默认值补齐，不崩", () => {
    expect(normalizeSettings({})).toEqual(createDefaultSettings());
    expect(normalizeSettings(null)).toEqual(createDefaultSettings());
    expect(normalizeSettings("not an object")).toEqual(createDefaultSettings());
    expect(normalizeSettings([])).toEqual(createDefaultSettings());
  });

  it("合法的字段被保留", () => {
    expect(
      normalizeSettings({
        theme: "light",
        fontScale: "xl",
        wallpaper: "dusk",
        reduceTransparency: true,
      }),
    ).toEqual({
      theme: "light",
      fontScale: "xl",
      wallpaper: "dusk",
      reduceTransparency: true,
    });
  });

  it("非法值回落到默认，不会把界面搞坏", () => {
    const s = normalizeSettings({
      theme: "rainbow",
      fontScale: "huge",
      wallpaper: "../../etc/passwd",
      reduceTransparency: "yes",
    });
    expect(s.theme).toBe("system");
    expect(s.fontScale).toBe("md");
    expect(s.wallpaper).toBe("fuji");
    expect(s.reduceTransparency).toBe(false);
  });

  it("字号档位的缩放系数单调递增", () => {
    const values = ["sm", "md", "lg", "xl"] as const;
    for (let i = 1; i < values.length; i += 1) {
      expect(FONT_SCALE_VALUES[values[i]]).toBeGreaterThan(FONT_SCALE_VALUES[values[i - 1]]);
    }
  });

  it("标准档不缩放", () => {
    expect(FONT_SCALE_VALUES.md).toBe(1);
  });
});
