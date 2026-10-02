import type { Lang } from './index'

/** The question box on the periodic table is parsed in English. For the other languages the question is first rewritten into
 *  the English phrasing the parser knows (stems and phrases per language, in the order they are applied), so "галогены,
 *  открытые до 1850" and "halogens discovered before 1850" give the same answer. */
type Rule = [string, string]
const L = '\\p{L}*'

const common: Rule[] = []

const ru: Rule[] = [
  ['(\\d)\\s*к(?![\\p{L}])', '$1 k'], ['°\\s*с(?![\\p{L}])', '°c'],
  ['(?:между|от)\\s+(-?\\d+(?:\\.\\d+)?)(\\s*[°\\p{L}]{0,7})?\\s+(?:и|до)\\s+(?=-?\\d)', ' between $1$2 and '],
  ['щелочноземельн' + L + '(?: металл' + L + ')?', ' alkaline earth metals '], ['щелочн' + L + '(?: металл' + L + ')?', ' alkali metals '],
  ['переходн' + L + '(?: металл' + L + ')?', ' transition metals '], ['(?:постпереходн' + L + '|друг' + L + ' металл' + L + ')', ' other metals '],
  ['металлоид' + L, ' metalloids '], ['неметалл' + L, ' nonmetals '], ['галоген' + L, ' halogens '],
  ['(?:инертн|благородн)' + L + ' газ' + L, ' noble gases '], ['(?:лантаноид|актиноид|редкоземельн)' + L, ' lanthanides '], ['металл' + L, ' metals '],
  ['тв[её]рд' + L, ' solid '], ['жидк' + L, ' liquid '], ['(?:газообразн|газ)' + L, ' gas '],
  ['при комнатной температуре', ' at room temperature '], ['при н\\.?\\s?у\\.?', ' at stp '], ['при (?=-?\\d)', ' at '],
  ['топ[- ](\\d+)', ' top $1 '],
  ['тяжел(?:ее|ый|ые|ая)(?= ?-?\\d)', ' heavier than '], ['(?:самый |самые )?тяжёл' + L, ' heaviest '], ['(?:самый |самые )?тяжел' + L, ' heaviest '],
  ['(?:самый |самые )?л[её]гк' + L, ' lightest '], ['л[её]гче(?= ?-?\\d)', ' lighter than '],
  ['(?:самый |самая |самое |самые )?(?:наибольш|наивысш|максимальн|высочайш|самый высок|самая высок)' + L, ' highest '],
  ['(?:самый |самая |самое |самые )?(?:наименьш|наинизш|минимальн|самый низк|самая низк)' + L, ' lowest '],
  ['самый больш' + L, ' largest '], ['самый маленьк' + L, ' smallest '],
  ['сродств' + L + ' к электрон' + L, ' electron affinity '], ['энерги' + L + ' ионизации', ' ionization energy '], ['ионизаци' + L, ' ionization '],
  ['ковалентн' + L + ' радиус' + L, ' covalent radius '], ['(?:радиус|размер)' + L, ' radius '],
  ['(?:температур' + L + ' )?плавлени' + L, ' melting point '], ['(?:температур' + L + ' )?кипени' + L, ' boiling point '],
  ['электроотрицательн' + L, ' electronegativity '], ['(?:атомн' + L + ' )?(?:масс|вес)' + L, ' mass '],
  ['(?:больше|выше|более|свыше|превышающ' + L + '|превышает)', ' above '], ['(?:меньше|ниже|менее)', ' below '],
  ['(?:открыт|найден|выделен|обнаружен)' + L, ' discovered '],
  ['до (\\d{3,4})', ' before $1 '], ['после (\\d{3,4})', ' after $1 '], ['(?:начиная )?с (\\d{3,4})', ' since $1 '], ['(?:к|не позднее) (\\d{3,4})', ' by $1 '], ['в (\\d{3,4})', ' in $1 '],
  ['(\\d{3,4})\\s*(?:году|года|г\\.|г)(?![\\p{L}])', '$1 '],
  ['(?:известн' + L + ' с древности|древн' + L + '|доисторическ' + L + ')', ' ancient '], ['степен' + L + ' окисления', ' oxidation state '],
  ['([spdf])[- ]блок' + L, ' $1-block '], ['(\\d+)(?:-?(?:й|го|ий|ого))? период' + L, ' period $1 '], ['период' + L + ' (\\d+)', ' period $1 '], ['(\\d+)(?:-?(?:я|й|ая))? групп' + L, ' group $1 '], ['групп' + L + ' (\\d+)', ' group $1 '],
  ['(?:радиоактивн|нестабильн|неустойчив)' + L, ' radioactive '], ['(?:стабильн|нерадиоактивн|устойчив)' + L, ' stable '],
  ['плотност' + L, ' density '], ['(?:электро)?проводимост' + L, ' conductivity '], ['цвет' + L, ' color '], ['тв[её]рдост' + L, ' hardness '], ['токсичн' + L, ' toxic '],
  ['(?:открыт|найден)' + L + ' (?:в|во) германи' + L, ' discovered in germany '],
  [' discovered (?:в|во|из) германи' + L, ' discovered in germany '], [' discovered (?:в|во|из) дани' + L, ' discovered in denmark '], [' discovered (?:в|во|из) испани' + L, ' discovered in spain '],
  [' discovered (?:в|во|из) финлянди' + L, ' discovered in finland '], [' discovered (?:в|во|из) франци' + L, ' discovered in france '], [' discovered (?:в|во|из) итали' + L, ' discovered in italy '],
  [' discovered (?:в|во|из) росси' + L, ' discovered in russia '], [' discovered (?:в|во|из) швеци' + L, ' discovered in sweden '],
  [' discovered (?:в|во|из) (?:великобритани|англи|британи)' + L, ' discovered in uk '], [' discovered (?:в|во|из) (?:сша|америк)' + L, ' discovered in usa '], [' discovered (?:в|во|из) япони' + L, ' discovered in japan '],
]

const uk: Rule[] = [
  ['(\\d)\\s*к(?![\\p{L}])', '$1 k'], ['°\\s*с(?![\\p{L}])', '°c'],
  ['(?:між|від)\\s+(-?\\d+(?:\\.\\d+)?)(\\s*[°\\p{L}]{0,7})?\\s+(?:і|та|до)\\s+(?=-?\\d)', ' between $1$2 and '],
  ['лужноземельн' + L + '(?: метал' + L + ')?', ' alkaline earth metals '], ['лужн' + L + '(?: метал' + L + ')?', ' alkali metals '],
  ['перехідн' + L + '(?: метал' + L + ')?', ' transition metals '], ['(?:постперехідн' + L + '|інш' + L + ' метал' + L + ')', ' other metals '],
  ['металоїд' + L, ' metalloids '], ['неметал' + L, ' nonmetals '], ['галоген' + L, ' halogens '],
  ['(?:інертн|шляхетн|благородн)' + L + ' газ' + L, ' noble gases '], ['(?:лантаноїд|актиноїд|рідкісноземельн)' + L, ' lanthanides '], ['метал' + L, ' metals '],
  ['тверд' + L, ' solid '], ['рідк' + L, ' liquid '], ['(?:газоподібн|газ)' + L, ' gas '],
  ['(?:за|при) кімнатн' + L + ' температур' + L, ' at room temperature '], ['при н\\.?\\s?у\\.?', ' at stp '], ['(?:за|при) (?=-?\\d)', ' at '],
  ['топ[- ](\\d+)', ' top $1 '], ['(?:найважч|найважк)' + L, ' heaviest '], ['важч' + L + '(?= ?-?\\d)', ' heavier than '],
  ['найлегш' + L, ' lightest '], ['легш' + L + '(?= ?-?\\d)', ' lighter than '],
  ['(?:найбільш|найвищ|максимальн)' + L, ' highest '], ['(?:найменш|найнижч|мінімальн)' + L, ' lowest '],
  ['спорідненість до електрон' + L, ' electron affinity '], ['енергі' + L + ' іонізації', ' ionization energy '], ['іонізаці' + L, ' ionization '],
  ['ковалентн' + L + ' радіус' + L, ' covalent radius '], ['(?:радіус|розмір)' + L, ' radius '],
  ['(?:температур' + L + ' )?плавлення', ' melting point '], ['(?:температур' + L + ' )?кипіння', ' boiling point '],
  ['електронегативн' + L, ' electronegativity '], ['(?:атомн' + L + ' )?(?:мас|ваг)' + L, ' mass '],
  ['(?:більше|вище|більш|понад|перевищу' + L + ')', ' above '], ['(?:менше|нижче|менш)', ' below '],
  ['(?:відкрит|знайден|виділен|виявлен)' + L, ' discovered '],
  ['до (\\d{3,4})', ' before $1 '], ['після (\\d{3,4})', ' after $1 '], ['(?:починаючи )?з (\\d{3,4})', ' since $1 '], ['(?:не пізніше) (\\d{3,4})', ' by $1 '], ['[вy] (\\d{3,4})', ' in $1 '], ['у (\\d{3,4})', ' in $1 '],
  ['(\\d{3,4})\\s*(?:році|року|р\\.|р)(?![\\p{L}])', '$1 '],
  ['(?:відом' + L + ' з давнини|давн' + L + '|доісторичн' + L + ')', ' ancient '], ['ступін' + L + ' окиснення', ' oxidation state '],
  ['([spdf])[- ]блок' + L, ' $1-block '], ['(\\d+)(?:-?(?:й|го|ий|ого))? період' + L, ' period $1 '], ['період' + L + ' (\\d+)', ' period $1 '], ['(\\d+)(?:-?(?:а|я|й))? груп' + L, ' group $1 '], ['груп' + L + ' (\\d+)', ' group $1 '],
  ['(?:радіоактивн|нестабільн|нестійк)' + L, ' radioactive '], ['(?:стабільн|нерадіоактивн|стійк)' + L, ' stable '],
  ['густин' + L, ' density '], ['(?:електро)?провідн' + L, ' conductivity '], ['колір|кольор' + L, ' color '], ['твердіст' + L, ' hardness '], ['токсичн' + L, ' toxic '],
  [' discovered (?:в|у|із|з) німеччин' + L, ' discovered in germany '], [' discovered (?:в|у|із|з) данi' + L, ' discovered in denmark '], [' discovered (?:в|у|із|з) іспані' + L, ' discovered in spain '],
  [' discovered (?:в|у|із|з) фінлянді' + L, ' discovered in finland '], [' discovered (?:в|у|із|з) франці' + L, ' discovered in france '], [' discovered (?:в|у|із|з) італі' + L, ' discovered in italy '],
  [' discovered (?:в|у|із|з) росі' + L, ' discovered in russia '], [' discovered (?:в|у|із|з) шведі' + L + '|швеці' + L, ' discovered in sweden '],
  [' discovered (?:в|у|із|з) (?:великобританi|англі|британі)' + L, ' discovered in uk '], [' discovered (?:в|у|із|з) (?:сша|америц|америк)' + L, ' discovered in usa '], [' discovered (?:в|у|із|з) японі' + L, ' discovered in japan '],
]

const zh: Rule[] = [
  ['\\s*(\\d+(?:\\.\\d+)?)\\s*(?:到|至|－|~)\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:之间)', ' between $1 and $2 '],
  ['(?:介于|在)\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:和|与|及)\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:之间)?', ' between $1 and $2 '],
  ['碱土金属', ' alkaline earth metals '], ['碱金属', ' alkali metals '], ['过渡金属', ' transition metals '], ['(?:后过渡金属|其他金属)', ' other metals '],
  ['(?:类金属|半金属)', ' metalloids '], ['非金属', ' nonmetals '], ['卤素', ' halogens '], ['(?:稀有气体|惰性气体|贵气体|稀有气体)', ' noble gases '],
  ['(?:镧系|锕系|稀土)(?:元素|金属)?', ' lanthanides '], ['金属', ' metals '],
  ['固体|固态', ' solid '], ['液体|液态', ' liquid '], ['气体|气态', ' gas '],
  ['(?:在)?室温(?:下)?', ' at room temperature '], ['标准状况(?:下)?', ' at stp '],
  ['前\\s*(\\d+)\\s*(?:个|种)?', ' top $1 '], ['最重', ' heaviest '], ['最轻', ' lightest '],
  ['(?:最高|最大|最多)', ' highest '], ['(?:最低|最小|最少)', ' lowest '],
  ['电子亲和(?:能|势)', ' electron affinity '], ['(?:第一)?电离能', ' ionization energy '], ['共价半径', ' covalent radius '], ['(?:范德华半径|原子半径|半径|大小)', ' radius '],
  ['熔点', ' melting point '], ['沸点', ' boiling point '], ['电负性', ' electronegativity '], ['(?:原子)?(?:质量|重量|原子量)', ' mass '],
  ['(?:大于|高于|超过|多于)', ' above '], ['(?:小于|低于|少于|不足)', ' below '],
  ['(\\d{3,4})\\s*年\\s*(?:之前|以前|前)', ' discovered before $1 '], ['(\\d{3,4})\\s*年\\s*(?:之后|以后|后)', ' discovered after $1 '],
  ['(?:自|从)\\s*(\\d{3,4})\\s*年(?:以来|起)?', ' discovered since $1 '], ['(?:在|于)?\\s*(\\d{3,4})\\s*年(?:被)?(?:发现)?(?:的)?', ' discovered in $1 '],
  ['(?:古代|史前|自古)(?:就)?(?:已知)?', ' ancient '], ['氧化(?:态|数)', ' oxidation state '],
  ['([spdf])\\s*区', ' $1-block '], ['第\\s*(\\d+)\\s*周期', ' period $1 '], ['第\\s*(\\d+)\\s*族', ' group $1 '],
  ['(?:放射性|不稳定)', ' radioactive '], ['稳定', ' stable '],
  ['密度', ' density '], ['(?:导电|电导)(?:性|率)?', ' conductivity '], ['颜色', ' color '], ['硬度', ' hardness '], ['毒性', ' toxic '],
  ['德国', ' discovered in germany '], ['丹麦', ' discovered in denmark '], ['西班牙', ' discovered in spain '], ['芬兰', ' discovered in finland '],
  ['法国', ' discovered in france '], ['意大利', ' discovered in italy '], ['俄罗斯', ' discovered in russia '], ['瑞典', ' discovered in sweden '],
  ['(?:英国|英格兰)', ' discovered in uk '], ['(?:美国|美利坚)', ' discovered in usa '], ['日本', ' discovered in japan '],
  ['发现(?:的)?', ' discovered '],
]

const es: Rule[] = [
  ['(?:entre)\\s+(-?\\d+(?:[.]\\d+)?)(\\s*[°\\p{L}]{0,7})?\\s+y\\s+(?=-?\\d)', ' between $1$2 and '],
  ['(?:metales? )?alcalino-?t[ée]rre' + L, ' alkaline earth metals '], ['(?:metales? )?alcalin' + L, ' alkali metals '],
  ['metales? de transici[oó]n|transici[oó]n', ' transition metals '], ['(?:otros metales|metales? (?:post|de post)-?transici[oó]n)', ' other metals '],
  ['metaloide' + L, ' metalloids '], ['no ?metal' + L, ' nonmetals '], ['hal[oó]geno' + L, ' halogens '], ['gas(?:es)? nobles?|gas(?:es)? raros?', ' noble gases '],
  ['(?:lant[aá]nido|act[ií]nido|tierras raras)' + L, ' lanthanides '], ['metal' + L, ' metals '],
  ['s[oó]lid' + L, ' solid '], ['l[ií]quid' + L, ' liquid '], ['gas(?:es|eos)?' + L, ' gas '],
  ['a (?:la )?temperatura ambiente', ' at room temperature '], ['en condiciones normales|en cn', ' at stp '],
  ['(?:los |las )?(?:primer[oa]s|top) (\\d+)', ' top $1 '], ['m[aá]s pesad' + L, ' heaviest '], ['m[aá]s (?:ligero|liviano)' + L, ' lightest '],
  ['(?:más pesado|más pesados) que(?= ?-?\\d)', ' heavier than '],
  ['(?:mayor|superior|m[aá]s de|por encima de|sobre|mayor o igual) (?:que |a |de )?(?=-?\\d)', ' above '],
  ['(?:menor|inferior|menos de|por debajo de|bajo) (?:que |a |de )?(?=-?\\d)', ' below '],
  ['a (?=-?\\d)', ' at '],
  ['(?:el |la |los |las )?(?:m[aá]s alt|mayor|m[aá]xim|m[aá]s grand)' + L, ' highest '], ['(?:el |la |los |las )?(?:m[aá]s baj|menor|m[ií]nim|m[aá]s peque[ñn])' + L, ' lowest '],
  ['afinidad electr[oó]nica', ' electron affinity '], ['energ[ií]a de ionizaci[oó]n', ' ionization energy '], ['ionizaci[oó]n', ' ionization '],
  ['radio covalente', ' covalent radius '], ['(?:radio|tama[ñn]o)' + L, ' radius '],
  ['punto de fusi[oó]n|fusi[oó]n', ' melting point '], ['punto de ebullici[oó]n|ebullici[oó]n', ' boiling point '],
  ['electronegatividad', ' electronegativity '], ['(?:masa|peso)(?: at[oó]mic[oa])?', ' mass '],
  ['(?:descubiert|aislad|encontrad|identificad)' + L, ' discovered '],
  ['(?:antes de|anteriores? a|previos? a)\\s+(?:el |del )?(?:a[ñn]o )?(\\d{3,4})', ' before $1 '], ['(?:despu[eé]s de|posteriores? a)\\s+(?:el |del )?(?:a[ñn]o )?(\\d{3,4})', ' after $1 '],
  ['desde\\s+(?:el )?(?:a[ñn]o )?(\\d{3,4})', ' since $1 '], ['hasta\\s+(?:el )?(?:a[ñn]o )?(\\d{3,4})', ' until $1 '], ['(?:en|durante)\\s+(?:el )?(?:a[ñn]o )?(\\d{3,4})', ' in $1 '],
  ['(?:conocid' + L + ' desde la antig[uü]edad|antig[uü]' + L + '|prehist[oó]ric' + L + ')', ' ancient '], ['(?:estado|n[uú]mero) de oxidaci[oó]n', ' oxidation state '],
  ['bloque\\s+([spdf])', ' $1-block '], ['per[ií]odo\\s+(\\d+)', ' period $1 '], ['grupo\\s+(\\d+)', ' group $1 '],
  ['(?:radiactiv|radioactiv|inestable)' + L, ' radioactive '], ['estable' + L, ' stable '],
  ['densidad', ' density '], ['conductividad', ' conductivity '], ['color', ' color '], ['dureza', ' hardness '], ['t[oó]xic' + L, ' toxic '],
  [' discovered (?:en|de) alemania', ' discovered in germany '], [' discovered (?:en|de) dinamarca', ' discovered in denmark '], [' discovered (?:en|de) espa[ñn]a', ' discovered in spain '],
  [' discovered (?:en|de) finlandia', ' discovered in finland '], [' discovered (?:en|de) francia', ' discovered in france '], [' discovered (?:en|de) italia', ' discovered in italy '],
  [' discovered (?:en|de) rusia', ' discovered in russia '], [' discovered (?:en|de) suecia', ' discovered in sweden '],
  [' discovered (?:en|de) (?:reino unido|inglaterra|gran breta[ñn]a)', ' discovered in uk '], [' discovered (?:en|de) (?:estados unidos|ee\\.? ?uu\\.?)', ' discovered in usa '], [' discovered (?:en|de) jap[oó]n', ' discovered in japan '],
]

const fr: Rule[] = [
  ['entre\\s+(-?\\d+(?:[.]\\d+)?)(\\s*[°\\p{L}]{0,7})?\\s+et\\s+(?=-?\\d)', ' between $1$2 and '],
  ['(?:m[ée]taux )?alcalino-?terr' + L, ' alkaline earth metals '], ['(?:m[ée]taux )?alcalin' + L, ' alkali metals '],
  ['m[ée]taux de transition|transition', ' transition metals '], ['(?:autres m[ée]taux|m[ée]taux pauvres)', ' other metals '],
  ['m[ée]tallo[iï]de' + L, ' metalloids '], ['non-? ?m[ée]ta' + L, ' nonmetals '], ['halog[èe]ne' + L, ' halogens '], ['gaz (?:nobles?|rares?)', ' noble gases '],
  ['(?:lanthanide|actinide|terres rares)' + L, ' lanthanides '], ['m[ée]ta(?:l|ux)', ' metals '],
  ['solide' + L, ' solid '], ['liquide' + L, ' liquid '], ['gaz(?:eux)?', ' gas '],
  ['[àa] (?:la )?temp[ée]rature ambiante', ' at room temperature '], ['(?:dans les )?conditions normales', ' at stp '],
  ['(?:les )?(\\d+) premiers?', ' top $1 '], ['(?:le |les )?plus lourd' + L, ' heaviest '], ['(?:le |les )?plus l[ée]ger' + L, ' lightest '],
  ['plus lourds? que(?= ?-?\\d)', ' heavier than '],
  ['(?:sup[ée]rieur|plus (?:grand|[ée]lev[ée])|plus de|au[- ]dessus de|d[ée]passant)(?:e|s|es)? (?:[àa] |que |de )?(?=-?\\d)', ' above '],
  ['(?:inf[ée]rieur|plus (?:petit|bas|faible)|moins de|en dessous de|au[- ]dessous de)(?:e|s|es)? (?:[àa] |que |de )?(?=-?\\d)', ' below '],
  ['[àa] (?=-?\\d)', ' at '],
  ['(?:le |la |les )?(?:plus (?:[ée]lev|grand|haut)|maximal|maximum)' + L, ' highest '], ['(?:le |la |les )?(?:plus (?:faible|bas|petit)|minimal|minimum)' + L, ' lowest '],
  ['affinit[ée] [ée]lectronique', ' electron affinity '], ['[ée]nergie d\'ionisation', ' ionization energy '], ['ionisation', ' ionization '],
  ['rayon covalent', ' covalent radius '], ['(?:rayon|taille)' + L, ' radius '],
  ['point de fusion|fusion', ' melting point '], ['point d\'[ée]bullition|[ée]bullition', ' boiling point '],
  ['[ée]lectron[ée]gativit[ée]', ' electronegativity '], ['(?:masse|poids)(?: atomique)?', ' mass '],
  ['(?:d[ée]couvert|isol[ée]|trouv[ée])' + L, ' discovered '],
  ['avant\\s+(?:l\'ann[ée]e\\s+)?(\\d{3,4})', ' before $1 '], ['apr[èe]s\\s+(?:l\'ann[ée]e\\s+)?(\\d{3,4})', ' after $1 '],
  ['depuis\\s+(?:l\'ann[ée]e\\s+)?(\\d{3,4})', ' since $1 '], ['jusqu\'(?:en|[àa])\\s+(\\d{3,4})', ' until $1 '], ['en\\s+(?:l\'ann[ée]e\\s+)?(\\d{3,4})', ' in $1 '],
  ['(?:connu' + L + ' depuis l\'antiquit[ée]|antiquit[ée]|antique|pr[ée]historique)' + L, ' ancient '], ['(?:[ée]tat|degr[ée]|nombre) d\'oxydation', ' oxidation state '],
  ['bloc\\s+([spdf])', ' $1-block '], ['p[ée]riode\\s+(\\d+)', ' period $1 '], ['groupe\\s+(\\d+)', ' group $1 '],
  ['(?:radioactif|radioactive|instable)' + L, ' radioactive '], ['stable' + L, ' stable '],
  ['densit[ée]', ' density '], ['conductivit[ée]', ' conductivity '], ['couleur', ' color '], ['duret[ée]', ' hardness '], ['toxique' + L, ' toxic '],
  [' discovered (?:en|d\'|de) allemagne', ' discovered in germany '], [' discovered (?:au|en|de) danemark', ' discovered in denmark '], [' discovered (?:en|d\'|de) espagne', ' discovered in spain '],
  [' discovered (?:en|de) finlande', ' discovered in finland '], [' discovered (?:en|de) france', ' discovered in france '], [' discovered (?:en|d\'|de) italie', ' discovered in italy '],
  [' discovered (?:en|de) russie', ' discovered in russia '], [' discovered (?:en|de) su[èe]de', ' discovered in sweden '],
  [' discovered (?:au|en|du) (?:royaume-uni|angleterre|grande-bretagne)', ' discovered in uk '], [' discovered (?:aux|en|des) [ée]tats-unis', ' discovered in usa '], [' discovered (?:au|en|du) japon', ' discovered in japan '],
]

const rules: Record<Lang, Rule[]> = { en: common, ru, uk, zh, es, fr }
/** The same rules as plain data (the Mac app reads them from queryvocab.json; see tools/export-query-vocab.mjs). */
export const queryRules = rules
const compiled = new Map<Lang, [RegExp, string][]>()
function compile(lang: Lang) {
  let c = compiled.get(lang)
  if (!c) {
    c = rules[lang].map(([p, r]) => {
      // letters in stems only match at the start of a word, so "газ" does not fire inside another word
      const noBoundary = lang === 'zh' || /^(\(\\d|°|\\s| )/.test(p)
      const boundary = noBoundary ? '' : '(?<![\\p{L}\\p{N}])'
      return [new RegExp(boundary + p, 'giu'), r] as [RegExp, string]
    })
    compiled.set(lang, c)
  }
  return c
}

/** Rewrites a question in `lang` into the English phrasing the parser understands. English is returned unchanged. */
export function normalizeQuery(raw: string, lang: Lang): string {
  if (lang === 'en') return raw
  let s = ' ' + raw.toLowerCase().replaceAll('’', "'").replaceAll('ʼ', "'") + ' '
  if (lang !== 'zh') s = s.replace(/(\d),(\d)/g, '$1.$2')
  for (const [re, rep] of compile(lang)) s = s.replace(re, rep).replace(/\s+/g, ' ')
  return s.replace(/\s+/g, ' ').trim()
}
