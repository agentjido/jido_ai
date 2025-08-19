// Requires window.initScheme() and window.toggleScheme() functions defined (see `color_scheme_switch.ex`)
const ColorSchemeHook = {
  deadViewCompatible: true,
  mounted() {
    // Only initialize if icons are in their default hidden state
    const darkIcon = this.el.querySelector(".color-scheme-dark-icon");
    const lightIcon = this.el.querySelector(".color-scheme-light-icon");
    if (
      darkIcon.classList.contains("hidden") &&
      lightIcon.classList.contains("hidden")
    ) {
      this.init();
    }
    this.el.addEventListener("click", window.toggleScheme);
  },
  updated() {
    // Only initialize if icons are in their default hidden state
    const darkIcon = this.el.querySelector(".color-scheme-dark-icon");
    const lightIcon = this.el.querySelector(".color-scheme-light-icon");
    if (
      darkIcon.classList.contains("hidden") &&
      lightIcon.classList.contains("hidden")
    ) {
      this.init();
    }
  },
  init() {
    initScheme();
  },
};

export default ColorSchemeHook;
