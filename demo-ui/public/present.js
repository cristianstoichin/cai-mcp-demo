// present.js — Present mode: self-driven tell-show-tell walkthrough (manual Next).
// Renders from the SAME scenarios.js as Demo/Overview; reuses trace.js renderers and
// the api client injected by app.js. Pure phaseSequence() is unit-tested under node.
// (Task 4 adds `import { renderCallRow } from "./trace.js";` when the view is added —
// relative import so this loads under both the browser (served from /) and node --test.)

// Pure: the ordered phases for a scene. Exported for unit tests.
export function phaseSequence(scene) {
  return ["tell-open", ...scene.calls.map((_, i) => `show:${i}`), "tell-close"];
}
