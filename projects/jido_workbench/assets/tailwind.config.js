// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const colors = require("tailwindcss/colors");
const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex",
    "../deps/petal_components/**/*.*ex",
  ],
  theme: {
    extend: {
      colors: {
        primary: colors.slate, // Changed to slate for a more subdued, professional look like ChatGPT/Anthropic
        secondary: colors.neutral, // Neutral works well for secondary elements
        success: colors.emerald,
        danger: colors.red,
        warning: colors.yellow,
        info: colors.gray, // Changed to gray for a more cohesive look
        gray: colors.gray,
      },
      fontFamily: {
        // Main text font - clean monospace
        mono: ["JetBrains Mono", "Share Tech Mono", "monospace"],
        // System text font
        sans: ["Inter", "system-ui", "sans-serif"],
        // Display/heading font
        display: ["VT323", "monospace"],
      },
    },
  },
  darkMode: "class",
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/typography"),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ])
    ),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized");
      let values = {};
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
          let name = path.basename(file, ".svg") + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, "");
            let size = theme("spacing.6");
            if (name.endsWith("-mini")) {
              size = theme("spacing.5");
            } else if (name.endsWith("-micro")) {
              size = theme("spacing.4");
            }
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: size,
              height: size,
            };
          },
        },
        { values }
      );
    }),
    plugin(function ({ addUtilities }) {
      addUtilities({
        ".neon-glow": {
          boxShadow:
            "0 0 5px theme(colors.success.400), 0 0 20px theme(colors.success.400)",
        },
        ".neon-border": {
          border: "1px solid theme(colors.success.400)",
          boxShadow: "0 0 5px theme(colors.success.400)",
        },
        ".animate-pulse-glow": {
          animation: "pulse-glow 2s cubic-bezier(0.4, 0, 0.6, 1) infinite",
        },
        "@keyframes pulse-glow": {
          "0%, 100%": {
            opacity: "1",
            boxShadow:
              "0 0 5px theme(colors.success.400), 0 0 20px theme(colors.success.400)",
          },
          "50%": {
            opacity: ".7",
            boxShadow:
              "0 0 2px theme(colors.success.400), 0 0 10px theme(colors.success.400)",
          },
        },
      });
    }),
  ],
};
