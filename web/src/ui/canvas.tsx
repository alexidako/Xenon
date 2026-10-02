import { useEffect, useRef } from 'preact/hooks'

/** A canvas that redraws when `deps` change or the element is resized. Draws in CSS pixels. */
export function Canvas({ draw, deps, class: cls, style, label, onRef }: {
  draw: (ctx: CanvasRenderingContext2D, w: number, h: number) => void; deps: unknown[]; class?: string; style?: Record<string, string | number>; label?: string
  onRef?: (c: HTMLCanvasElement | null) => void
}) {
  const ref = useRef<HTMLCanvasElement>(null)
  const paint = () => {
    const c = ref.current; if (!c) return
    const r = c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1
    const w = Math.max(1, Math.round(r.width)), h = Math.max(1, Math.round(r.height))
    if (c.width !== w * dpr || c.height !== h * dpr) { c.width = w * dpr; c.height = h * dpr }
    const ctx = c.getContext('2d')!; ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h)
    draw(ctx, w, h)
  }
  useEffect(paint, deps)
  useEffect(() => { onRef?.(ref.current); const ro = new ResizeObserver(paint); if (ref.current) ro.observe(ref.current); return () => ro.disconnect() }, deps)
  return <canvas ref={ref} class={cls} style={style} role="img" aria-label={label} />
}

export const cssVar = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()
