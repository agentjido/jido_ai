const ScrollBottom = {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    // Ensure the DOM is updated before scrolling
    requestAnimationFrame(() => this.scrollToBottom());
  },
  scrollToBottom() {
    const messagesContainer = this.el;
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  },
};

export default ScrollBottom;
