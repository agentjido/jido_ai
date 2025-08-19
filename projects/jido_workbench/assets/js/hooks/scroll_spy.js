export default {
  mounted() {
    this.setupSmoothScroll();
    this.setupScrollSpy();
  },

  setupSmoothScroll() {
    // Handle all anchor clicks in the navigation
    this.el.querySelectorAll('a[href^="#"]').forEach((anchor) => {
      anchor.addEventListener("click", (e) => {
        e.preventDefault();
        const targetId = anchor.getAttribute("href").slice(1);
        const targetElement = document.getElementById(targetId);

        if (targetElement) {
          targetElement.scrollIntoView({
            behavior: "smooth",
            block: "start",
          });
          // Update URL without jumping
          history.pushState(null, null, `#${targetId}`);
        }
      });
    });
  },

  setupScrollSpy() {
    const sections = document.querySelectorAll(
      "h1[id], h2[id], h3[id], section[id]"
    );
    const navLinks = this.el.querySelectorAll('a[href^="#"]');

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            // Remove active class from all links
            navLinks.forEach((link) => {
              link.classList.remove("text-lime-500", "bg-zinc-800");
              link.classList.add("text-zinc-300");
            });

            // Add active class to corresponding link
            const activeLink = this.el.querySelector(
              `a[href="#${entry.target.id}"]`
            );
            if (activeLink) {
              activeLink.classList.remove("text-zinc-300");
              activeLink.classList.add("text-lime-500", "bg-zinc-800");
            }
          }
        });
      },
      {
        rootMargin: "-20% 0px -80% 0px", // Adjust these values to control when sections become "active"
      }
    );

    sections.forEach((section) => observer.observe(section));
  },
};
