import gleam from "vite-gleam";
import tailwindcss from "@tailwindcss/vite";

import wasm from "vite-plugin-wasm";
import topLevelAwait from "vite-plugin-top-level-await";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  // build: {
  //   emptyOutDir: true,
  //   outDir: "../priv/dist",
  // },
  plugins: [react(), gleam(), wasm(), topLevelAwait()],
  optimizeDeps: {
    exclude: ["@matrix-org/matrix-sdk-crypto-wasm"],
  },
  // server: {
  //     proxy: {
  //           '': 'http://localhost:4000',
  //     }
  // }
});
