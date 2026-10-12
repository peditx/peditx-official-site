/* Theme catalogue for the picker.

   The CSS for all of these lives in src/styles/global.css as [data-theme=...]
   blocks; this file only carries what the picker needs to draw its buttons.
   `swatch` is the brand colour of the theme, `light` groups the light ones so
   the picker can label them. Keep the two lists in sync. */

export interface Theme {
  id: string;
  name: string;
  swatch: string;
  light: boolean;
}

export const DEFAULT_THEME = 'tokyo-night';

export const THEMES: Theme[] = [
  { id: 'catppuccin', name: 'Catppuccin', swatch: '#89b4fa', light: false },
  { id: 'catppuccin-latte', name: 'Catppuccin Latte', swatch: '#1e66f5', light: true },
  { id: 'ethereal', name: 'Ethereal', swatch: '#7d82d9', light: false },
  { id: 'everforest', name: 'Everforest', swatch: '#7fbbb3', light: false },
  { id: 'flexoki-light', name: 'Flexoki Light', swatch: '#205ea6', light: true },
  { id: 'gruvbox', name: 'Gruvbox', swatch: '#7daea3', light: false },
  { id: 'hackerman', name: 'Hackerman', swatch: '#82fb9c', light: false },
  { id: 'kanagawa', name: 'Kanagawa', swatch: '#dcd7ba', light: false },
  { id: 'last-horizon', name: 'Last Horizon', swatch: '#b59790', light: false },
  { id: 'lumon', name: 'Lumon', swatch: '#8bc9eb', light: false },
  { id: 'lupine', name: 'Lupine', swatch: '#3264eb', light: true },
  { id: 'matte-black', name: 'Matte Black', swatch: '#e68e0d', light: false },
  { id: 'miasma', name: 'Miasma', swatch: '#78824b', light: false },
  { id: 'nord', name: 'Nord', swatch: '#81a1c1', light: false },
  { id: 'osaka-jade', name: 'Osaka Jade', swatch: '#509475', light: false },
  { id: 'retro-82', name: 'Retro 82', swatch: '#faa968', light: false },
  { id: 'ristretto', name: 'Ristretto', swatch: '#f38d70', light: false },
  { id: 'rose-pine', name: 'Rose Pine', swatch: '#56949f', light: true },
  { id: 'solitude', name: 'Solitude', swatch: '#798186', light: false },
  { id: 'tokyo-night', name: 'Tokyo Night', swatch: '#9ece6a', light: false },
  { id: 'vantablack', name: 'Vantablack', swatch: '#8d8d8d', light: false },
  { id: 'white', name: 'White', swatch: '#6e6e6e', light: true },
];

export const STORAGE_KEY = 'peditx-theme';

export const themeById = (id: string): Theme =>
  THEMES.find((t) => t.id === id) ?? THEMES.find((t) => t.id === DEFAULT_THEME)!;
