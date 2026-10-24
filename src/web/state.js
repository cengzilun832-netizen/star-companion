const STORAGE_KEY = 'starcompanion.web.v1'
const GATE_KEY = 'starcompanion.web.gate.v1'

export function dayStamp(date = new Date()) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

export function hashString(value) {
  let hash = 2166136261
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

export function dailyScores(sign) {
  const seed = `${dayStamp()}:${sign}`
  return {
    overall: 76 + (hashString(`${seed}:overall`) % 17),
    love: 69 + (hashString(`${seed}:love`) % 27),
    work: 69 + (hashString(`${seed}:work`) % 27),
    money: 69 + (hashString(`${seed}:money`) % 27),
    mood: 69 + (hashString(`${seed}:mood`) % 27),
  }
}

function defaultState() {
  return {
    language: 'zh-Hant',
    name: '',
    sign: 'libra',
    skin: 'classic',
    petDay: dayStamp(),
    food: 3,
    pats: 0,
    tarot: null,
  }
}

export function loadState() {
  const fallback = defaultState()
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null')
    if (!parsed || typeof parsed !== 'object') return fallback
    const state = { ...fallback, ...parsed }
    if (state.petDay !== dayStamp()) {
      state.petDay = dayStamp()
      state.food = 3
      state.pats = 0
    }
    return state
  } catch {
    return fallback
  }
}

export function saveState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
  } catch {
    // The app remains usable when browser storage is unavailable.
  }
}

export function shouldShowGate() {
  try {
    const params = new URLSearchParams(location.search)
    return params.has('ritual') || localStorage.getItem(GATE_KEY) !== dayStamp()
  } catch {
    return false
  }
}

export function markGateSeen() {
  try {
    localStorage.setItem(GATE_KEY, dayStamp())
  } catch {
    // The opening ceremony may return next visit in private browsing.
  }
}
