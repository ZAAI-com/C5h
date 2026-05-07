import { useEffect } from "react";
import { useStore } from "@/app/store";

export function useAppInit() {
  const initialize = useStore((state) => state.initialize);
  const isLoading = useStore((state) => state.isLoading);
  const error = useStore((state) => state.error);

  useEffect(() => {
    initialize();
  }, [initialize]);

  return { isLoading, error };
}
