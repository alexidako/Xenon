/** Camera state for a molecule viewer: the model rotates about its own centre and the camera only moves in and out,
 *  within limits, so the model can never be dragged out of view. */
export type Quat = [number, number, number, number]   // x, y, z, w
export const qmul = (a: Quat, b: Quat): Quat => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1], a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3], a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]
export const qaxis = (angle: number, x: number, y: number, z: number): Quat => { const s = Math.sin(angle / 2); return [x * s, y * s, z * s, Math.cos(angle / 2)] }
export const qnorm = (q: Quat): Quat => { const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1; return [q[0] / l, q[1] / l, q[2] / l, q[3] / l] }

export class Trackball {
  orientation: Quat; readonly initial: Quat; distance: number
  constructor(readonly base: number, tilt: { x: number; y: number } = { x: 0, y: 0 }) {
    this.initial = qmul(qaxis(tilt.x, 1, 0, 0), qaxis(tilt.y, 0, 1, 0)); this.orientation = this.initial; this.distance = base
  }
  get minDistance() { return this.base * 0.3 }
  get maxDistance() { return this.base * 2.0 }
  /** Drag by (dx, dy) screen points: horizontal drag spins about the vertical axis, vertical drag about the horizontal axis. */
  rotate(dx: number, dy: number) { this.orientation = qnorm(qmul(qmul(qaxis(dy * 0.01, 1, 0, 0), qaxis(dx * 0.01, 0, 1, 0)), this.orientation)) }
  /** Positive amount = zoom in. */
  zoom(amount: number) { this.distance = Math.min(this.maxDistance, Math.max(this.minDistance, this.distance * Math.exp(-amount))) }
  reset() { this.orientation = this.initial; this.distance = this.base }
}
