import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src-react/test/setup.ts"],
    include: ["src-react/**/*.{test,spec}.{ts,tsx}"],
    coverage: {
      reporter: ["text", "html", "lcov"],
      exclude: [
        "node_modules/",
        "src-react/test/",
        "src-react/vite-env.d.ts",
        "*.config.{ts,js}",
      ],
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src-react"),
    },
  },
});
