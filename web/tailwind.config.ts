import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // 品牌固定色（对应 Palette.swift，不随主题变）
        klein: "#002FA7",
        "klein-deep": "#001F77",
        amber: "#F5A845",
        cadmium: "#FDD835",
        ink: "#3D3326",
        cream: "#F6EFDF",
        kraft: "#D5C4A8",
        faceplate: "#29292E",
        // 语义色（随主题切换，值见 globals.css 的 CSS 变量）
        surface: "var(--surface)",
        card: "var(--card)",
        chip: "var(--chip)",
        label: "var(--label)",
      },
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
      },
      animation: {
        "pulse-slow": "pulse 2.4s ease-in-out infinite",
        "float-hint": "float-hint 2.6s ease-in-out infinite",
      },
      keyframes: {
        "float-hint": {
          "0%, 100%": { transform: "translateY(0)", opacity: "0.5" },
          "50%": { transform: "translateY(4px)", opacity: "1" },
        },
      },
    },
  },
  plugins: [],
};
export default config;
