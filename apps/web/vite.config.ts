import tailwindcss from "@tailwindcss/vite";
import viteReact from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url))
    }
  },
  optimizeDeps: {
    exclude: ["@avalsys/account-av-web", "@avalsys/apps-av-web"]
  },
  server: {
    port: 5195
  },
  plugins: [viteReact(), tailwindcss()]
});
