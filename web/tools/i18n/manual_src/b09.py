_blk = {'s': ('s', 's', 's', 's', 's'), 'p': ('p', 'p', 'p', 'p', 'p'), 'd': ('d', 'd', 'd', 'd', 'd'), 'f': ('f', 'f', 'f', 'f', 'f')}
_grp = ('Группа', 'Група', '第 {n} 族', 'Grupo', 'Groupe')
B = [
    (f"{b}-Block", f"{b}-блок", f"{b}-блок", f"{b} 区", f"Bloque {b}", f"Bloc {b}") for b in 'spdf'
] + [
    (f"Group {n}", f"Группа {n}", f"Група {n}", f"第 {n} 族", f"Grupo {n}", f"Groupe {n}") for n in range(1, 9)
] + [
    ("Solid", "Твёрдое", "Тверде", "固体", "Sólido", "Solide"),
    ("Liquid", "Жидкое", "Рідке", "液体", "Líquido", "Liquide"),
    ("Unknown", "Неизвестно", "Невідомо", "未知", "Desconocido", "Inconnu"),
]
