export default {
  mounted() {
    this.highlight();
  },
  updated() {
    this.highlight();
  },
  highlight() {
    const blocks = this.el.querySelectorAll("pre code");
    blocks.forEach((block) => {
      hljs.highlightElement(block);
    });
  },
};
