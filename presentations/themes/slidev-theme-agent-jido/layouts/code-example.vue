<template>
  <div class="slidev-layout code-example">
    <slot />
  </div>
</template>

<style>
.slidev-layout.code-example {
  display: grid;
  grid-template-columns: 1fr 3rem 1.3fr; /* text, gutter, code */
  align-items: start;
  gap: 0;
  padding: 3rem 2rem;
  height: 100vh;
  box-sizing: border-box;
}

.slidev-layout.code-example > *:not(pre):not(.shiki) {
  grid-column: 1;
  font-size: 1.5rem;
  line-height: 1.6;
  align-self: center;
}

.slidev-layout.code-example h1,
.slidev-layout.code-example h2,
.slidev-layout.code-example h3 {
  margin-bottom: 1.5rem;
  grid-column: 1 / -1; /* Title spans full width */
  margin-bottom: 2rem;
}

.slidev-layout.code-example ul,
.slidev-layout.code-example ol {
  margin: 0;
  padding-left: 1.5rem;
}

.slidev-layout.code-example li {
  margin-bottom: 0.8rem;
}

.slidev-layout.code-example pre,
.slidev-layout.code-example .shiki {
  grid-column: 3;
  margin: 0 !important;
  width: 100%;
  max-height: 70vh;
  overflow-y: auto;
  font-size: 1.1rem;
  line-height: 1.4;
  border-radius: 8px;
  align-self: center;
}

.slidev-layout.code-example .shiki {
  padding: 1.5rem !important;
}

/* Responsive adjustments */
@media (max-width: 768px) {
  .slidev-layout.code-example {
    grid-template-columns: 1fr;
    grid-template-rows: auto auto;
    gap: 1rem;
  }
  
  .slidev-layout.code-example pre,
  .slidev-layout.code-example .shiki {
    grid-column: 1;
  }
}
</style>
