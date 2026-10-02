const P: Record<string, string> = {
  grid: 'M3 3h5v5H3zM10 3h5v5h-5zM17 3h4v5h-4zM3 10h5v5H3zM10 10h5v5h-5zM17 10h4v5h-4zM3 17h5v4H3zM10 17h5v4h-5zM17 17h4v4h-4z',
  nuclide: 'M12 3a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM5 14a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM19 14a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM10.5 8.5l-4 6M13.5 8.5l4 6M8 17h8',
  chart: 'M3 3v18h18M7 15l4-5 3 3 5-7',
  wave: 'M2 12h4l3-8 4 16 3-8h6',
  quiz: 'M4 4h16v12H9l-5 4zM9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .8-1 1.5M12 14.5v.5',
  boxes: 'M3 6h18v12H3zM9 6v12M15 6v12',
  book: 'M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM4 19V5M8 7h7',
  pen: 'M4 20l1-4L17 4l3 3L8 19zM14 7l3 3',
  atom: 'M12 12m-1.5 0a1.5 1.5 0 1 0 3 0 1.5 1.5 0 1 0-3 0M12 12m-9 0a9 3.6 0 1 0 18 0 9 3.6 0 1 0-18 0M12 12m-9 0a9 3.6 60 1 0 18 0 9 3.6 60 1 0-18 0M12 12m-9 0a9 3.6 120 1 0 18 0 9 3.6 120 1 0-18 0',
  orbital: 'M12 3c3 0 3 7 0 9-3-2-3-9 0-9zM12 21c3 0 3-7 0-9-3 2-3 9 0 9zM3 12c0-3 7-3 9 0-2 3-9 3-9 0zM21 12c0 3-7 3-9 0 2-3 9-3 9 0z',
  link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
  fx: 'M9 4c-2 0-2 2-2.5 6M5 10h6M6.5 10C6 16 6 20 4 20M14 11l6 7M20 11l-6 7',
  equals: 'M5 9h14M5 15h14M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z',
  share: 'M12 3v12M8 7l4-4 4 4M5 13v7h14v-7',
  warn: 'M12 3l10 18H2zM12 10v5M12 18v.5',
  tablecells: 'M3 4h18v16H3zM3 10h18M3 15h18M9 4v16M15 4v16',
  flask: 'M9 3h6M10 3v6L4 19a2 2 0 0 0 2 3h12a2 2 0 0 0 2-3l-6-10V3M7 15h10',
  gear: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4-4',
}
export function Icon({ name }: { name: string }) {
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={P[name] ?? P.grid} /></svg>
}
