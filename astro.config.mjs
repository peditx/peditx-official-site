import { defineConfig } from 'astro/config';
import tailwind from "@astrojs/tailwind";

// https://astro.build/config
export default defineConfig({
  site: 'https://codes.peditx.ir',
  output: 'static',
  integrations: [tailwind()],
});

