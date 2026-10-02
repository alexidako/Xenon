import { useEffect, useState } from 'preact/hooks'

/** A tiny observable value, optionally persisted in localStorage. */
export class Store<T> {
  private listeners = new Set<() => void>()
  constructor(private value: T, private key?: string) {
    if (key) { try { const raw = localStorage.getItem(key); if (raw != null) this.value = { ...(value as object), ...JSON.parse(raw) } as T } catch { /* defaults */ } }
  }
  get(): T { return this.value }
  set(v: T | ((old: T) => T)) {
    this.value = typeof v === 'function' ? (v as (o: T) => T)(this.value) : v
    if (this.key) { try { localStorage.setItem(this.key, JSON.stringify(this.value)) } catch { /* ignore */ } }
    this.listeners.forEach(l => l())
  }
  subscribe(l: () => void) { this.listeners.add(l); return () => { this.listeners.delete(l) } }
}

export function useStore<T>(s: Store<T>): T {
  const [, force] = useState(0)
  useEffect(() => s.subscribe(() => force(n => n + 1)), [s])
  return s.get()
}
