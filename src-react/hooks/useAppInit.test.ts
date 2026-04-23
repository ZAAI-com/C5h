import { describe, expect, it, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { useAppInit } from "./useAppInit";
import { useStore } from "@/store";

describe("useAppInit", () => {
  let initialize: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.clearAllMocks();
    initialize = vi.fn().mockResolvedValue(undefined);
    useStore.setState({
      initialize: initialize as unknown as () => Promise<void>,
      isLoading: false,
      error: null,
    });
  });

  it("calls initialize on mount", async () => {
    renderHook(() => useAppInit());

    await waitFor(() => expect(initialize).toHaveBeenCalledTimes(1));
  });

  it("does not re-call initialize on re-render", async () => {
    const { rerender } = renderHook(() => useAppInit());

    await waitFor(() => expect(initialize).toHaveBeenCalledTimes(1));

    rerender();
    rerender();

    expect(initialize).toHaveBeenCalledTimes(1);
  });

  it("returns isLoading from store", () => {
    useStore.setState({ isLoading: true });
    const { result } = renderHook(() => useAppInit());
    expect(result.current.isLoading).toBe(true);
  });

  it("returns error from store", () => {
    useStore.setState({ error: "Something failed" });
    const { result } = renderHook(() => useAppInit());
    expect(result.current.error).toBe("Something failed");
  });
});
