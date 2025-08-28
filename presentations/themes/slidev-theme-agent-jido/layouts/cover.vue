<script setup lang="ts">
const props = defineProps<{
  title?: string
  subtitle?: string
  eyebrow?: string
  ctaPrimaryText?: string
  ctaPrimaryHref?: string
  ctaSecondaryText?: string
  ctaSecondaryHref?: string
}>()
</script>

<template>
  <div class="slidev-layout cover">
    <div class="max-w-6xl mx-auto px-6 py-20">
      <header class="flex items-center justify-between text-sm text-slate-400/90 mb-14">
        <div class="brand-name text-3xl text-slate-300">AGENT JIDO</div>
        <div class="flex items-center gap-5 opacity-80">
          <div class="i-carbon-book text-xl" />
          <div class="i-carbon-notebook text-xl" />
          <div class="i-carbon-blog text-xl" />
        </div>
      </header>
      <main class="text-center">
        <div v-if="props.eyebrow" class="small-eyebrow mb-3">{{ props.eyebrow }}</div>
        <h1 class="mb-4">{{ props.title }}</h1>
        <p v-if="props.subtitle" class="text-slate-400">{{ props.subtitle }}</p>
        <div class="mt-10 inline-flex gap-4">
          <a v-if="props.ctaPrimaryText" class="aj-border rounded-md px-5 py-2 text-slate-200 hover:bg-white/5 aj-glow" :href="props.ctaPrimaryHref || '#'">
            {{ props.ctaPrimaryText }}
          </a>
        </div>
      </main>
    </div>
  </div>
</template>
