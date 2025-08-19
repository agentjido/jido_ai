const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const content = this.el.dataset.content;
      navigator.clipboard.writeText(content);
    });
  },
};

export default CopyToClipboard;
