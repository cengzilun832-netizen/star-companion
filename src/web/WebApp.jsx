import { useEffect, useState } from 'react'
import { Icon } from '../icons'
import { copy, languages } from './content'
import { dayStamp, loadState, markGateSeen, saveState, shouldShowGate } from './state'
import { DailyGate, PetScreen, ProfileScreen, TarotScreen, TodayScreen } from './Screens'
import classicStar from '../../assets/pet/skins/lucky-star-wave.png'

const navigation = [['today', 'today', 'today'], ['tarot', 'tarot', 'ask'], ['pet', 'pet', 'pet'], ['profile', 'profile', 'profile']]

export default function WebApp() {
  const [state, setState] = useState(loadState)
  const [tab, setTab] = useState('today')
  const [gate, setGate] = useState(shouldShowGate)
  const [opening, setOpening] = useState(false)
  const locale = languages.includes(state.language) ? state.language : 'zh-Hant'
  const t = copy[locale]

  useEffect(() => { saveState(state) }, [state])
  useEffect(() => { document.documentElement.lang = locale; document.title = `${t.brand} · ${t[tab]}` }, [locale, t, tab])

  function openGate() {
    if (opening) return
    setOpening(true)
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    window.setTimeout(() => { markGateSeen(); setGate(false); setOpening(false) }, reduceMotion ? 150 : 1050)
  }

  function navigate(next) {
    setTab(next)
    window.scrollTo({ top: 0, behavior: 'instant' })
  }

  function changeLanguage(next) {
    setState((current) => ({ ...current, language: next }))
  }

  const todaysReading = state.tarot?.day === dayStamp() ? state.tarot : null

  return (
    <div className="web-app">
      <a className="skip-link" href="#main-content">{t.today}</a>
      <div className="app-content" aria-hidden={gate} inert={gate}>
      <header className="web-header">
        <button className="brand-button" onClick={() => navigate('today')} aria-label={t.brand}><img src={classicStar} alt="" /><span><strong>{t.brand}</strong><small>{t.tagline}</small></span></button>
        <nav className="desktop-nav" aria-label={t.brand}>{navigation.map(([key, label, icon]) => <button key={key} onClick={() => navigate(key)} className={tab === key ? 'is-active' : ''} aria-current={tab === key ? 'page' : undefined}><Icon name={icon} size={20} />{t[label]}</button>)}</nav>
        <label className="header-language"><Icon name="globe" size={17} /><span className="sr-only">{t.language}</span><select value={locale} onChange={(event) => changeLanguage(event.target.value)} aria-label={t.language}><option value="zh-Hant">繁體中文</option><option value="en">English</option><option value="ko">한국어</option></select></label>
      </header>

      {tab === 'today' && <TodayScreen t={t} locale={locale} state={state} onNavigate={navigate} />}
      {tab === 'tarot' && <TarotScreen t={t} locale={locale} reading={todaysReading} onDraw={(reading) => setState((current) => ({ ...current, tarot: reading }))} />}
      {tab === 'pet' && <PetScreen t={t} state={state} updateState={setState} />}
      {tab === 'profile' && <ProfileScreen t={t} locale={locale} state={state} updateState={setState} onLanguage={changeLanguage} />}

      <nav className="mobile-nav" aria-label={t.brand}>{navigation.map(([key, label, icon]) => <button key={key} onClick={() => navigate(key)} className={tab === key ? 'is-active' : ''} aria-current={tab === key ? 'page' : undefined}><Icon name={icon} size={22} /><span>{t[label]}</span></button>)}</nav>
      </div>
      {gate && <DailyGate t={t} locale={locale} opening={opening} onOpen={openGate} />}
    </div>
  )
}
