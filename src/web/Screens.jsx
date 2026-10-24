import { useState } from 'react'
import { Icon } from '../icons'
import { tarotCards, zodiac, languageIndex } from './content'
import { dailyScores, dayStamp, hashString } from './state'
import heroArt from '../../assets/web/stargazing-garden.png'
import petHabitat from '../../assets/pet/star-pet-habitat.png'
import classicStar from '../../assets/pet/skins/lucky-star-wave.png'
import auroraStar from '../../assets/pet/skins/lucky-star-skin-aurora.png'
import moonveilStar from '../../assets/pet/skins/lucky-star-skin-moonveil.png'
import azureStar from '../../assets/pet/skins/lucky-star-skin-azure-butterfly-v2.png'
import frostStar from '../../assets/pet/skins/lucky-star-skin-frost-nocturne-v2.png'
import eclipseStar from '../../assets/pet/skins/lucky-star-skin-eclipse.png'
import tarotStar from '../../assets/ip/lucky-star-tarot.png'
import doorClosed from '../../assets/ritual/magic-door-closed.png'
import doorOpen from '../../assets/ritual/magic-door-open.png'

const looks = [
  ['classic', classicStar, 'skinClassic'],
  ['aurora', auroraStar, 'skinAurora'],
  ['moonveil', moonveilStar, 'skinMoonveil'],
  ['azure', azureStar, 'skinAzure'],
  ['frost', frostStar, 'skinFrost'],
  ['eclipse', eclipseStar, 'skinEclipse'],
]

const topics = [['love', 'topicLove', 'heart'], ['work', 'topicWork', 'briefcase'], ['today', 'topicToday', 'sparkle']]
const categories = [['love', 'catLove', 'heart'], ['work', 'catWork', 'briefcase'], ['money', 'catMoney', 'coin'], ['mood', 'catMood', 'cloud']]

function formatDate(locale) {
  return new Intl.DateTimeFormat(locale, { month: 'long', day: 'numeric', weekday: 'long' }).format(new Date())
}

function Starfield() {
  return <div className="starfield" aria-hidden="true"><i /><i /><i /><i /><i /><i /><i /><i /></div>
}

export function DailyGate({ t, locale, opening, onOpen }) {
  return (
    <div className={`web-gate ${opening ? 'is-opening' : ''}`} role="dialog" aria-modal="true" aria-label={t.gateTitle}>
      <img className="gate-back" src={doorOpen} alt="" />
      <img className="gate-front" src={doorClosed} alt="" />
      <div className="gate-shine" aria-hidden="true" />
      <div className="gate-content">
        <p className="gate-date">{formatDate(locale)}</p>
        <h1>{t.gateTitle}</h1>
        <p>{t.gateBody}</p>
        <button className="primary-action" onClick={onOpen} disabled={opening}>
          <Icon name="sparkle" size={19} /> {opening ? t.gateOpening : t.gateOpen} <Icon name="chevron" size={17} />
        </button>
      </div>
    </div>
  )
}

export function TodayScreen({ t, locale, state, onNavigate }) {
  const [activeCategory, setActiveCategory] = useState('love')
  const [guideOpen, setGuideOpen] = useState(false)
  const [guideFlipped, setGuideFlipped] = useState(false)
  const scores = dailyScores(state.sign)
  const noteIndex = categories.findIndex(([key]) => key === activeCategory)
  const sign = zodiac.find(([key]) => key === state.sign)

  return (
    <main id="main-content" className="today-page">
      <section className="today-hero" aria-labelledby="today-title">
        <div className="hero-art-wrap">
          <img className="hero-art" src={heroArt} alt="" />
          <span className="hero-art-glint glint-one" aria-hidden="true">✦</span>
          <span className="hero-art-glint glint-two" aria-hidden="true">✧</span>
        </div>
        <div className="hero-reading">
          <Starfield />
          <div className="hero-reading-inner">
            <p className="today-date">{formatDate(locale)}</p>
            <h1 id="today-title">{t.headline}</h1>
            <div className="hero-rule" aria-hidden="true"><span>✦</span></div>
            <div className="score-display"><span>{t.overall}</span><strong>{scores.overall}</strong></div>
            <p className="today-intro">{t.intro}</p>
            <button className="primary-action" onClick={() => { setGuideOpen(true); setGuideFlipped(false) }}>
              <Icon name="ask" size={19} /> {t.guideOpen} <Icon name="chevron" size={17} />
            </button>
          </div>
        </div>
      </section>

      <section className="fortune-lower" aria-labelledby="categories-title">
        <div className="fortune-categories">
          <h2 id="categories-title">{t.categories}</h2>
          <div className="category-list">
            {categories.map(([key, label, icon], index) => (
              <button key={key} className={`category-item ${activeCategory === key ? 'is-active' : ''}`} onClick={() => setActiveCategory(key)} aria-pressed={activeCategory === key}>
                <span className="category-icon"><Icon name={icon} size={24} filled={icon === 'heart'} /></span>
                <span className="category-name">{t[label]}</span>
                <strong>{scores[key]}</strong>
                <Icon name="chevron" size={17} />
                <small>{t.notes[index]}</small>
              </button>
            ))}
          </div>
          <p className="category-detail" aria-live="polite">{t.notes[noteIndex]}</p>
        </div>
        <button className="tarot-teaser" onClick={() => onNavigate('tarot')}>
          <span className="teaser-card" aria-hidden="true"><Icon name="sparkle" size={34} /></span>
          <span><small>{t.tarotTease}</small><strong>{t.tarotTeaseText}</strong><em>{t.tarotGo} <Icon name="chevron" size={16} /></em></span>
        </button>
      </section>
      <p className="footnote">{sign ? sign[languageIndex(locale) + 1] : ''} · {t.disclaimer}</p>

      {guideOpen && (
        <div className="modal-backdrop" onMouseDown={() => setGuideOpen(false)}>
          <section className="guide-modal" role="dialog" aria-modal="true" aria-labelledby="guide-title" onMouseDown={(event) => event.stopPropagation()}>
            <button className="modal-close" onClick={() => setGuideOpen(false)} aria-label={t.close}><Icon name="close" size={20} /></button>
            <div className={`guide-flip ${guideFlipped ? 'is-flipped' : ''}`}>
              <div className="guide-flip-inner">
                <button className="guide-face guide-back" onClick={() => setGuideFlipped(true)} aria-label={t.flip} tabIndex={guideFlipped ? -1 : 0}><Icon name="sparkle" size={62} /><span>{t.flip}</span></button>
                <div className="guide-face guide-front"><img src={tarotStar} alt="" /><span>✦</span></div>
              </div>
            </div>
            <h2 id="guide-title">{guideFlipped ? t.guideTitle : t.guideOpen}</h2>
            {guideFlipped && <p>{t.guideText}</p>}
            {guideFlipped && <button className="secondary-action" onClick={() => setGuideOpen(false)}>{t.guideClose}</button>}
          </section>
        </div>
      )}
    </main>
  )
}

export function TarotScreen({ t, locale, reading, onDraw }) {
  const [topic, setTopic] = useState('today')
  const [question, setQuestion] = useState('')
  const [flipped, setFlipped] = useState(Boolean(reading))
  const card = reading ? tarotCards[reading.cardIndex] : null
  const langIndex = languageIndex(locale)

  function draw() {
    if (reading?.day === dayStamp()) { setFlipped(true); return }
    const seed = hashString(`${dayStamp()}:${topic}:${question.trim()}`)
    onDraw({ day: dayStamp(), topic, question: question.trim().slice(0, 120), cardIndex: seed % tarotCards.length, reversed: seed % 3 === 0 })
    setFlipped(false)
  }

  const todaysReading = reading?.day === dayStamp() ? reading : null

  return (
    <main id="main-content" className="feature-page tarot-page">
      <div className="feature-copy">
        <p className="feature-date">{formatDate(locale)}</p>
        <h1>{t.tarotTitle}</h1>
        <p className="feature-intro">{t.tarotIntro}</p>
        <div className="topic-picker" role="group" aria-label={t.tarotTitle}>
          {topics.map(([key, label, icon]) => <button key={key} className={topic === key ? 'is-active' : ''} onClick={() => setTopic(key)} aria-pressed={topic === key} disabled={Boolean(todaysReading)}><Icon name={icon} size={21} />{t[label]}</button>)}
        </div>
        <label className="question-label" htmlFor="tarot-question">{t.question}</label>
        <textarea id="tarot-question" value={question} onChange={(event) => setQuestion(event.target.value)} maxLength={120} placeholder={t.questionPlaceholder} disabled={Boolean(todaysReading)} />
        <button className="primary-action tarot-draw" onClick={draw}>{todaysReading ? t.returnToCard : t.draw}<Icon name="chevron" size={17} /></button>
        <p className="subtle-note">{todaysReading ? t.drawAgainTomorrow : t.disclaimer}</p>
      </div>
      <div className="tarot-stage">
        <div className="tarot-stage-stars" aria-hidden="true">✧ &nbsp; ✦ &nbsp; ✧</div>
        <div className={`tarot-card ${flipped ? 'is-flipped' : ''} ${todaysReading ? 'has-reading' : ''}`}>
          <div className="tarot-card-inner">
            <button className="tarot-card-face tarot-card-back" onClick={() => todaysReading && setFlipped(true)} disabled={!todaysReading || flipped} aria-label={t.flip}><Icon name="sparkle" size={70} /><span>{todaysReading ? t.flip : t.cardBack}</span></button>
            <div className="tarot-card-face tarot-card-front"><img src={tarotStar} alt="" /><small>{todaysReading?.reversed ? t.reversed : t.upright}</small><strong>{card?.name[langIndex]}</strong></div>
          </div>
        </div>
        {flipped && card && <div className="reading-result" aria-live="polite"><h2>{card.name[langIndex]}</h2><p>{card.meaning[langIndex]}</p>{todaysReading.question && <small>{t.questionEcho}：{todaysReading.question}</small>}</div>}
      </div>
    </main>
  )
}

export function PetScreen({ t, state, updateState }) {
  const [message, setMessage] = useState('')
  const [wardrobeOpen, setWardrobeOpen] = useState(false)
  const look = looks.find(([key]) => key === state.skin) || looks[0]

  function interact(type) {
    if (type === 'feed') {
      if (state.food <= 0) { setMessage(t.petNoFood); return }
      updateState((current) => ({ ...current, food: current.food - 1 }))
    } else {
      if (state.pats >= 3) { setMessage(t.petLimit); return }
      updateState((current) => ({ ...current, pats: current.pats + 1 }))
    }
    setMessage(t.petHappy)
  }

  return (
    <main id="main-content" className="feature-page pet-page">
      <section className="pet-intro"><h1>{t.petTitle}</h1><p>{t.petIntro}</p></section>
      <div className="pet-world"><img className="pet-habitat" src={petHabitat} alt="" /><img className="pet-character" src={look[1]} alt={t[look[2]]} /><span className="pet-shimmer" aria-hidden="true">✦</span></div>
      <section className="pet-controls" aria-label={t.petName}>
        <div className="pet-summary"><strong>{t.petName}</strong><p>{message || t.petHappy}</p><span>{t.petSaved}</span></div>
        <div className="pet-actions"><button className="primary-action" onClick={() => interact('feed')} disabled={state.food <= 0}><Icon name="food" size={21} />{t.petFeed}<small>{state.food}/3</small></button><button className="secondary-action" onClick={() => interact('pat')} disabled={state.pats >= 3}><Icon name="heart" size={21} />{t.petTouch}<small>{state.pats}/3</small></button></div>
        <button className="wardrobe-toggle" onClick={() => setWardrobeOpen(!wardrobeOpen)} aria-expanded={wardrobeOpen}><Icon name="pet" size={20} />{t.petWardrobe}<Icon name="chevron" size={18} /></button>
        {wardrobeOpen && <div className="wardrobe-list">{looks.map(([key, image, name]) => <button key={key} className={state.skin === key ? 'is-active' : ''} onClick={() => updateState((current) => ({ ...current, skin: key }))} aria-pressed={state.skin === key}><img src={image} alt="" /><span>{t[name]}</span><small>{state.skin === key ? t.petSelected : t.petSelect}</small></button>)}</div>}
      </section>
    </main>
  )
}

export function ProfileScreen({ t, locale, state, updateState, onLanguage }) {
  const [name, setName] = useState(state.name)
  const [sign, setSign] = useState(state.sign)
  const [feedback, setFeedback] = useState('')
  const [feedbackStatus, setFeedbackStatus] = useState('')
  const langIndex = languageIndex(locale)

  async function sendFeedback() {
    if (!feedback.trim()) { setFeedbackStatus(t.feedbackEmpty); return }
    const body = feedback.trim().slice(0, 2000)
    const url = `https://github.com/cengzilun832-netizen/star-companion/issues/new?title=${encodeURIComponent('Star Companion web feedback')}&body=${encodeURIComponent(body)}`
    window.open(url, '_blank', 'noopener,noreferrer')
    try { await navigator.clipboard.writeText(body); setFeedbackStatus(t.feedbackCopied) }
    catch { setFeedbackStatus(t.feedbackManual) }
  }

  return (
    <main id="main-content" className="profile-page">
      <div className="profile-heading"><img src={classicStar} alt="" /><div><h1>{t.profileTitle}</h1><p>{t.browserOnly}</p></div></div>
      <div className="profile-grid">
        <section className="profile-section" aria-labelledby="personal-title"><h2 id="personal-title">{t.yourName}</h2><label htmlFor="profile-name">{t.yourName}</label><input id="profile-name" value={name} maxLength={24} onChange={(event) => setName(event.target.value)} placeholder={t.namePlaceholder} /><label htmlFor="profile-sign">{t.zodiacLabel}</label><select id="profile-sign" value={sign} onChange={(event) => setSign(event.target.value)}>{zodiac.map(([key]) => <option key={key} value={key}>{zodiac.find(([id]) => id === key)[langIndex + 1]}</option>)}</select><button className="primary-action" onClick={() => updateState((current) => ({ ...current, name: name.trim(), sign }))}>{t.save}</button></section>
        <section className="profile-section" aria-labelledby="language-title"><h2 id="language-title">{t.language}</h2><div className="language-options"><button className={locale === 'zh-Hant' ? 'is-active' : ''} onClick={() => onLanguage('zh-Hant')} aria-pressed={locale === 'zh-Hant'}>繁體中文</button><button className={locale === 'en' ? 'is-active' : ''} onClick={() => onLanguage('en')} aria-pressed={locale === 'en'}>English</button><button className={locale === 'ko' ? 'is-active' : ''} onClick={() => onLanguage('ko')} aria-pressed={locale === 'ko'}>한국어</button></div><h2>{t.privacyTitle}</h2><p>{t.privacyText}</p></section>
        <section className="profile-section feedback-section" aria-labelledby="feedback-title"><h2 id="feedback-title">{t.feedbackTitle}</h2><p>{t.feedbackIntro}</p><textarea value={feedback} onChange={(event) => setFeedback(event.target.value)} maxLength={2000} placeholder={t.feedbackPlaceholder} /><button className="secondary-action" onClick={sendFeedback}>{t.feedbackSend}<Icon name="chevron" size={17} /></button><p className="feedback-status" role="status">{feedbackStatus}</p></section>
      </div>
      <p className="footnote">{t.disclaimer}</p>
    </main>
  )
}
