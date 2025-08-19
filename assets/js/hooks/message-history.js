const MessageHistory = {
  mounted() {
    this.handleKeyDown = this.handleKeyDown.bind(this);
    this.el.addEventListener("keydown", this.handleKeyDown);
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.handleKeyDown);
  },

  handleKeyDown(event) {
    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault();
      this.pushEventTo(this.el, "keydown", { key: event.key });
    }
  },
};

export default MessageHistory;
