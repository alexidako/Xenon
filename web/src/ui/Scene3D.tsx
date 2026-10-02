import { useEffect, useRef } from 'preact/hooks'
import * as THREE from 'three'
import { Trackball } from '../lib/trackball'
import { t } from '../i18n'

function disposeTree(o: THREE.Object3D, keep: Set<unknown>) {
  o.traverse(c => {
    const m = c as THREE.Mesh
    if (m.geometry && !keep.has(m.geometry)) m.geometry.dispose()
    const mats = Array.isArray(m.material) ? m.material : m.material ? [m.material] : []
    for (const mat of mats) { (mat as THREE.MeshBasicMaterial).map?.dispose(); mat.dispose() }
  })
}

/** A WebGL viewer with a fixed camera and trackball rotation. Drag to rotate, scroll or pinch to zoom, double-click to reset.
 *  Increase `resetToken` to reset from outside. When `sceneKey` changes the content is swapped in place and the user's rotation and zoom are kept. */
export function Scene3D({ build, distance, tilt = { x: 0, y: 0 }, resetToken = 0, sceneKey, hint = 'Drag to rotate · scroll to zoom · double-click to reset', height, label = '3D view', keepGeometry }: {
  build: () => THREE.Object3D; distance: number; tilt?: { x: number; y: number }; resetToken?: number; sceneKey: string; hint?: string; height?: number | string; label?: string
  keepGeometry?: THREE.BufferGeometry[]            // shared geometries that must not be disposed on swap
}) {
  const host = useRef<HTMLDivElement>(null)
  const st = useRef<{ renderer: THREE.WebGLRenderer; scene: THREE.Scene; camera: THREE.PerspectiveCamera; pivot: THREE.Group; ball: Trackball; content: THREE.Object3D | null; key: string; token: number; base: number; raf: number } | null>(null)

  useEffect(() => {
    const el = host.current!
    let renderer: THREE.WebGLRenderer
    try { renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false }) } catch { el.textContent = '3D graphics are not available in this browser.'; return }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2)); renderer.setClearColor(0x1a1a1a, 1)
    renderer.domElement.style.cssText = 'width:100%;height:100%;display:block;touch-action:none;cursor:grab'
    renderer.domElement.setAttribute('role', 'img'); renderer.domElement.setAttribute('aria-label', t(label))
    el.prepend(renderer.domElement)
    const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera(60, 1, 0.1, 500), pivot = new THREE.Group()
    scene.add(pivot); scene.add(new THREE.AmbientLight(0xffffff, 0.75))
    const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(-4, 6, 8); scene.add(key)
    const fill = new THREE.DirectionalLight(0xffffff, 0.5); fill.position.set(6, -3, 4); scene.add(fill)
    const s = { renderer, scene, camera, pivot, ball: new Trackball(distance, tilt), content: null as THREE.Object3D | null, key: '', token: resetToken, base: distance, raf: 0 }
    st.current = s
    if (import.meta.env.DEV) (window as unknown as Record<string, unknown>).__xenon3d = s
    const apply = () => { const q = s.ball.orientation; pivot.quaternion.set(q[0], q[1], q[2], q[3]); camera.position.set(0, 0, s.ball.distance); render() }
    const render = () => { renderer.render(scene, camera) }
    const resize = () => { const w = el.clientWidth || 300, h = el.clientHeight || 300; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); render() }
    const ro = new ResizeObserver(resize); ro.observe(el)
    let last: { x: number; y: number } | null = null, mode: 'rotate' | 'zoom' = 'rotate', lastClick = 0
    const pointers = new Map<number, { x: number; y: number }>(); let pinch = 0
    const c = renderer.domElement
    c.onpointerdown = e => {
      c.setPointerCapture(e.pointerId); pointers.set(e.pointerId, { x: e.clientX, y: e.clientY }); last = { x: e.clientX, y: e.clientY }; mode = e.button === 2 ? 'zoom' : 'rotate'
      const now = performance.now(); if (now - lastClick < 350 && pointers.size === 1) { s.ball.reset(); apply(); lastClick = 0 } else lastClick = now
      if (pointers.size === 2) { const [a, b] = [...pointers.values()]; pinch = Math.hypot(a.x - b.x, a.y - b.y) }
      c.style.cursor = 'grabbing'
    }
    c.onpointermove = e => {
      if (!pointers.has(e.pointerId)) return
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY })
      if (pointers.size === 2) { const [a, b] = [...pointers.values()], d = Math.hypot(a.x - b.x, a.y - b.y); if (pinch) s.ball.zoom((d - pinch) * 0.01); pinch = d; apply(); return }
      if (!last) return
      const dx = e.clientX - last.x, dy = e.clientY - last.y; last = { x: e.clientX, y: e.clientY }
      if (mode === 'rotate') s.ball.rotate(dx, dy); else s.ball.zoom(-dy * 0.01)
      apply()
    }
    const up = (e: PointerEvent) => { pointers.delete(e.pointerId); last = null; pinch = 0; c.style.cursor = 'grab' }
    c.onpointerup = up; c.onpointercancel = up; c.oncontextmenu = e => e.preventDefault()
    c.addEventListener('wheel', e => { e.preventDefault(); s.ball.zoom(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.002)); apply() }, { passive: false })
    resize(); apply()
    return () => { ro.disconnect(); if (s.content) disposeTree(s.content, new Set()); renderer.dispose(); renderer.domElement.remove(); st.current = null }
  }, [])

  // swap content when the key changes
  useEffect(() => {
    const s = st.current; if (!s) return
    if (s.content) { s.pivot.remove(s.content); disposeTree(s.content, new Set(keepGeometry ?? [])) }
    s.content = build(); s.pivot.add(s.content); s.key = sceneKey
    if (distance !== s.base) { const q = s.ball.orientation, d = s.ball.distance / s.base; s.ball = new Trackball(distance, tilt); s.ball.orientation = q; s.ball.distance = Math.min(s.ball.maxDistance, Math.max(s.ball.minDistance, distance * d)); s.base = distance }
    const qq = s.ball.orientation; s.pivot.quaternion.set(qq[0], qq[1], qq[2], qq[3]); s.camera.position.set(0, 0, s.ball.distance); s.renderer.render(s.scene, s.camera)
    const raf = requestAnimationFrame(() => st.current?.renderer.render(s.scene, s.camera)); return () => cancelAnimationFrame(raf)
  }, [sceneKey, distance])

  useEffect(() => { const s = st.current; if (!s || s.token === resetToken) return; s.token = resetToken; s.ball.reset(); const q = s.ball.orientation; s.pivot.quaternion.set(q[0], q[1], q[2], q[3]); s.camera.position.set(0, 0, s.ball.distance); s.renderer.render(s.scene, s.camera) }, [resetToken])

  return <div ref={host} class="canvasbox" style={{ height: height ?? '100%', minHeight: 240, background: '#1a1a1a', position: 'relative' }}><div class="hint">{t(hint)}</div></div>
}
