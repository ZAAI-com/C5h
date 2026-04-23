import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { renderHook } from "@testing-library/react";
import { useKeyboardShortcuts } from "./useKeyboardShortcuts";

function dispatchKey(key: string, opts: { meta?: boolean; target?: HTMLElement } = {}) {
  const event = new KeyboardEvent("keydown", {
    key,
    metaKey: opts.meta ?? false,
    bubbles: true,
    cancelable: true,
  });
  if (opts.target) {
    Object.defineProperty(event, "target", { value: opts.target, writable: false });
    opts.target.dispatchEvent(event);
  } else {
    window.dispatchEvent(event);
  }
  return event;
}

describe("useKeyboardShortcuts", () => {
  let onSwitchTab: ReturnType<typeof vi.fn>;
  let onStartWindow: ReturnType<typeof vi.fn>;
  let onJumpToToday: ReturnType<typeof vi.fn>;
  let onNavigateWeek: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    onSwitchTab = vi.fn();
    onStartWindow = vi.fn();
    onJumpToToday = vi.fn();
    onNavigateWeek = vi.fn();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("Cmd+1 switches to calendar tab", () => {
    renderHook(() => useKeyboardShortcuts({ onSwitchTab }));
    dispatchKey("1", { meta: true });
    expect(onSwitchTab).toHaveBeenCalledWith("calendar");
  });

  it("Cmd+2 switches to stats tab", () => {
    renderHook(() => useKeyboardShortcuts({ onSwitchTab }));
    dispatchKey("2", { meta: true });
    expect(onSwitchTab).toHaveBeenCalledWith("stats");
  });

  it("Cmd+3 switches to settings tab", () => {
    renderHook(() => useKeyboardShortcuts({ onSwitchTab }));
    dispatchKey("3", { meta: true });
    expect(onSwitchTab).toHaveBeenCalledWith("settings");
  });

  it("Cmd+N starts new window", () => {
    renderHook(() => useKeyboardShortcuts({ onStartWindow }));
    dispatchKey("n", { meta: true });
    expect(onStartWindow).toHaveBeenCalledTimes(1);
  });

  it("Cmd+T jumps to today", () => {
    renderHook(() => useKeyboardShortcuts({ onJumpToToday }));
    dispatchKey("t", { meta: true });
    expect(onJumpToToday).toHaveBeenCalledTimes(1);
  });

  it("ArrowLeft navigates to previous week", () => {
    renderHook(() => useKeyboardShortcuts({ onNavigateWeek }));
    dispatchKey("ArrowLeft");
    expect(onNavigateWeek).toHaveBeenCalledWith("prev");
  });

  it("ArrowRight navigates to next week", () => {
    renderHook(() => useKeyboardShortcuts({ onNavigateWeek }));
    dispatchKey("ArrowRight");
    expect(onNavigateWeek).toHaveBeenCalledWith("next");
  });

  it("Arrow keys are ignored when focus is in an input", () => {
    renderHook(() => useKeyboardShortcuts({ onNavigateWeek }));
    const input = document.createElement("input");
    document.body.appendChild(input);
    dispatchKey("ArrowLeft", { target: input });
    expect(onNavigateWeek).not.toHaveBeenCalled();
    document.body.removeChild(input);
  });

  it("Arrow keys are ignored when meta is held (treated as system shortcut)", () => {
    renderHook(() => useKeyboardShortcuts({ onNavigateWeek }));
    dispatchKey("ArrowLeft", { meta: true });
    expect(onNavigateWeek).not.toHaveBeenCalled();
  });

  it("listener is removed on unmount", () => {
    const { unmount } = renderHook(() => useKeyboardShortcuts({ onSwitchTab }));
    unmount();
    dispatchKey("1", { meta: true });
    expect(onSwitchTab).not.toHaveBeenCalled();
  });
});
