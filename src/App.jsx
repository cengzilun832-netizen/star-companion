import { useEffect, useMemo, useRef, useState } from 'react'
import { fortunes, readings } from './data'
import { Icon } from './icons'
import { generatedPetSkins, petSkinCategories } from './petSkinCollection'
import luckyStarWave from '../assets/pet/skins/lucky-star-wave.png'
import luckyStarTarot from '../assets/ip/lucky-star-tarot.png'
import luckyStarSleep from '../assets/ip/lucky-star-sleep.png'
import luckyStarCelebrate from '../assets/ip/lucky-star-celebrate.png'
import luckyStarCelebrateGif from '../assets/pet/lucky-star-celebrate.gif'
import luckyStarSkinAurora from '../assets/pet/skins/lucky-star-skin-aurora.png'
import luckyStarSkinEclipse from '../assets/pet/skins/lucky-star-skin-eclipse.png'
import luckyStarSkinMoonveil from '../assets/pet/skins/lucky-star-skin-moonveil.png'
import luckyStarSkinLunarTide from '../assets/pet/skins/lucky-star-skin-lunar-tide-v2.png'
import luckyStarSkinAzureButterfly from '../assets/pet/skins/lucky-star-skin-azure-butterfly-v2.png'
import luckyStarSkinFrostNocturne from '../assets/pet/skins/lucky-star-skin-frost-nocturne-v2.png'
import starPetHabitat from '../assets/pet/star-pet-habitat.png'
import celestialGarden from '../assets/celestial-garden.png'
import magicDoorClosed from '../assets/ritual/magic-door-closed.png'
import magicDoorOpen from '../assets/ritual/magic-door-open.png'

const DAILY_GATE_STORAGE_KEY = 'yunshi.daily-gate.v1'
const PROFILE_STORAGE_KEY = 'yunshi.profile.v1'
const WECHAT_SESSION_STORAGE_KEY = 'xingban.wechat-session.v1'
const PET_PLANET_STORAGE_KEY = 'xingban.shared-planet.v3'
const HOME_STORAGE_KEY = 'yunshi.little-home.v1'
const DAILY_PET_LIMIT = 3
const STAR_PASS_DAILY_LIMIT = 8
const FEED_COST = 10

const readingStarStyleByCard = {
  節制: { name: '平衡極光', image: luckyStarSkinAurora },
  女祭司: { name: '月霧直覺', image: luckyStarSkinMoonveil },
  月亮: { name: '月蝕夢境', image: luckyStarSkinEclipse },
  死神: { name: '冰晶蛻變', image: luckyStarSkinFrostNocturne },
  default: { name: '璀璨星光', image: luckyStarCelebrate },
}

const demoWechatFriends = [
  { id: 'xiaoyu', name: '小雨', emoji: '🌙', color: 'violet' },
  { id: 'ahe', name: '阿禾', emoji: '🌱', color: 'green' },
  { id: 'xiaoyu2', name: '小宇', emoji: '☁️', color: 'blue' },
]

function loadStoredProfile() {
  if (typeof window === 'undefined') return null
  try {
    const stored = window.localStorage.getItem(PROFILE_STORAGE_KEY)
    return stored ? JSON.parse(stored) : null
  } catch {
    return null
  }
}

function loadStoredWechatSession() {
  if (typeof window === 'undefined') return null
  try {
    const stored = window.localStorage.getItem(WECHAT_SESSION_STORAGE_KEY)
    return stored ? JSON.parse(stored) : null
  } catch {
    return null
  }
}

function loadStoredPlanet() {
  const fallback = {
    stardust: 72,
    feedCount: 2,
    dailyFeedCount: 0,
    bonusFeedCredits: 0,
    starTaskClaimed: false,
    taskDone: false,
    interactionDay: getLocalDayStamp(),
    petCountToday: 0,
    subscriptionPlan: 'free',
    petLevel: 1,
    selectedSkin: 'classic',
    friendIds: ['xiaoyu'],
    activity: '小雨剛剛餵了小星',
  }
  if (typeof window === 'undefined') return fallback
  try {
    const stored = window.localStorage.getItem(PET_PLANET_STORAGE_KEY)
    const parsed = stored ? JSON.parse(stored) : null
    const planet = parsed ? { ...fallback, ...parsed } : fallback
    if (!parsed?.subscriptionPlan) planet.subscriptionPlan = parsed?.isStarPassMember ? 'orbit' : 'free'
    if (!parsed?.petLevel) planet.petLevel = planet.taskDone ? 2 : 1
    if (planet.interactionDay !== getLocalDayStamp()) {
      const dailySupply = planet.subscriptionPlan === 'orbit' ? 20 : planet.subscriptionPlan === 'star' ? 10 : 0
      return { ...planet, interactionDay: getLocalDayStamp(), petCountToday: 0, feedCount: 0, dailyFeedCount: 0, bonusFeedCredits: 0, starTaskClaimed: false, taskDone: false, stardust: Math.min(200, planet.stardust + dailySupply) }
    }
    return planet
  } catch {
    return fallback
  }
}

const homeFurniture = [
  { id: 'moon-lamp', name: '月光小燈', icon: '☾', accent: 'gold' },
  { id: 'star-rug', name: '星軌地毯', icon: '✦', accent: 'rose' },
  { id: 'night-plant', name: '夜色盆栽', icon: '♧', accent: 'leaf' },
  { id: 'astro-frame', name: '星象畫框', icon: '☌', accent: 'violet' },
  { id: 'comet-cushion', name: '流星抱枕', icon: '☄', accent: 'blue' },
]

function loadStoredHome() {
  const fallback = {
    day: getLocalDayStamp(),
    taskIds: [],
    claimedToday: false,
    owned: ['moon-lamp', 'star-rug'],
    placed: ['moon-lamp', 'star-rug'],
  }
  if (typeof window === 'undefined') return fallback
  try {
    const stored = window.localStorage.getItem(HOME_STORAGE_KEY)
    const home = stored ? { ...fallback, ...JSON.parse(stored) } : fallback
    return home.day === getLocalDayStamp() ? home : { ...home, day: getLocalDayStamp(), taskIds: [], claimedToday: false }
  } catch {
    return fallback
  }
}

function getZodiac(dateString) {
  if (!dateString) return ''
  const [, monthValue, dayValue] = dateString.split('-').map(Number)
  const edge = monthValue * 100 + dayValue
  const signs = [
    [120, '摩羯座'], [219, '水瓶座'], [321, '雙魚座'], [420, '牡羊座'],
    [521, '金牛座'], [622, '雙子座'], [723, '巨蟹座'], [823, '獅子座'],
    [923, '處女座'], [1024, '天秤座'], [1123, '天蠍座'], [1222, '射手座'], [1232, '摩羯座'],
  ]
  return signs.find(([limit]) => edge < limit)?.[1] || '摩羯座'
}

function formatBirthday(dateString) {
  if (!dateString) return '尚未設定'
  const [year, month, day] = dateString.split('-')
  return `${year}年${Number(month)}月${Number(day)}日`
}

function getLocalDayStamp(date = new Date()) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function getDisplayDate(date = new Date()) {
  const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
  return `${date.getMonth() + 1}月${date.getDate()}日・${weekdays[date.getDay()]}`
}

function shouldShowDailyGate() {
  if (typeof window === 'undefined') return false
  return new URLSearchParams(window.location.search).get('ritual') === '1'
}

function StatusBar() {
  return (
    <div className="status-bar" aria-hidden="true">
      <span>9:41</span>
      <div className="status-icons"><i className="signal"/><i className="wifi"/><i className="battery"/></div>
    </div>
  )
}

function AppHeader({ title = '運勢', onSettings, back, showDate = false }) {
  return (
    <header className={`app-header ${back ? 'simple' : ''}`}>
      {back ? <button className="icon-button" onClick={back} aria-label="返回"><Icon name="back"/></button> : <span className="header-spacer" />}
      <div className="header-title">
        <h1>{title}</h1>
        {showDate && <p>{getDisplayDate()}</p>}
      </div>
      {back || !onSettings ? <span className="header-spacer" /> : <button className="icon-button" onClick={onSettings} aria-label="設定"><Icon name="settings"/></button>}
    </header>
  )
}

function DailyGate({ phase, onOpen }) {
  const opening = phase === 'opening'

  return (
    <main className={`daily-gate ${opening ? 'opening' : ''}`} aria-label="每日魔法門">
      <img className="gate-art gate-art-open" src={magicDoorOpen} alt="" aria-hidden="true" />
      <img className="gate-art gate-art-closed" src={magicDoorClosed} alt="關閉的魔法門" />
      <div className="gate-door-motion" aria-hidden="true">
        <span className="gate-leaf gate-leaf-left">
          <img src={magicDoorClosed} alt="" />
        </span>
        <span className="gate-leaf gate-leaf-right">
          <img src={magicDoorClosed} alt="" />
        </span>
      </div>
      <div className="gate-light" aria-hidden="true" />
      <div className="gate-unlock" aria-hidden="true"><span>✦</span></div>
      <div className="gate-sparkles" aria-hidden="true">
        <i/><i/><i/><i/><i/><i/>
      </div>
      <div className="gate-transition-veil" aria-hidden="true" />
      <StatusBar />
      <header className="gate-brand">
        <h1>運勢</h1>
        <p>{getDisplayDate()}</p>
      </header>
      <section className="gate-copy">
        <h2>今天的門，為你打開</h2>
        <p>門後藏著只屬於今天的指引</p>
        <button className="primary-button gate-button" onClick={onOpen} disabled={opening}>
          <Icon name="sparkle" size={21}/>
          <span>{opening ? '門正在打開…' : '推開魔法門'}</span>
          <Icon name="chevron" size={21}/>
        </button>
      </section>
    </main>
  )
}

function FortuneCategory({ item, active, onClick }) {
  return (
    <button className={`fortune-category ${active ? 'active' : ''}`} onClick={onClick} aria-pressed={active}>
      <span className="category-icon"><Icon name={item.icon} size={21} filled={item.icon === 'heart'} /></span>
      <span>{item.label}</span>
      <strong>{item.score}</strong>
    </button>
  )
}

function TodayScreen({ onAsk, onSettings, profile }) {
  const [selected, setSelected] = useState(null)
  const [guideOpen, setGuideOpen] = useState(false)
  const activeFortune = selected ? fortunes[selected] : null

  return (
    <main className="screen today-screen">
      <section className="world-hero">
        <StatusBar />
        <AppHeader onSettings={onSettings} showDate />
        <div className="twinkle twinkle-one"/><div className="twinkle twinkle-two"/><div className="twinkle twinkle-three"/>
      </section>

      <section className="fortune-panel" aria-label="今日運勢">
        <div className="panel-stars" aria-hidden="true">✦ <span>✦</span></div>
        <h2>今天，慢慢來會更幸運</h2>
        <p className="score-label">綜合運勢</p>
        <div className="overall-score">82</div>

        <div className="category-row">
          {Object.entries(fortunes).map(([key, item]) => (
            <FortuneCategory key={key} item={item} active={selected === key} onClick={() => setSelected(selected === key ? null : key)} />
          ))}
        </div>

        <div className={`category-note ${activeFortune ? 'visible' : ''}`} aria-live="polite">
          {activeFortune?.note || '點一下分類，看今天的小提醒。'}
        </div>

        <div className="source-line"><span>✦</span> {profile?.zodiac || '你的星座'} ・ 星象 ・ 塔羅：星星 <span>▥</span></div>

        <button className="primary-button" onClick={() => setGuideOpen(true)}>
          <Icon name="sparkle" size={22}/><span>翻開今日指引</span><Icon name="chevron" size={21}/>
        </button>

        <button className="ask-entry" onClick={onAsk}>
          <img className="entry-ip" src={luckyStarWave} alt="" />
          <span>有件事想問宇宙？</span>
          <strong>問一問 <Icon name="chevron" size={17}/></strong>
        </button>
      </section>

      {guideOpen && <GuideSheet onClose={() => setGuideOpen(false)} />}
    </main>
  )
}

function GuideSheet({ onClose }) {
  return (
    <div className="sheet-backdrop" onMouseDown={onClose}>
      <section className="bottom-sheet" onMouseDown={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="guide-title">
        <div className="sheet-handle" />
        <button className="sheet-close" onClick={onClose} aria-label="關閉"><Icon name="close" size={20}/></button>
        <img className="guide-ip" src={luckyStarTarot} alt="拿著塔羅牌的幸運星" />
        <p className="sheet-kicker">今日塔羅・星星</p>
        <h2 id="guide-title">相信那個還很微小的希望</h2>
        <p>今天不需要一次想清楚所有事。先照顧好自己的節奏，答案會在你往前走的時候出現。</p>
        <div className="lucky-row"><span>幸運色：霧粉紫</span><span>幸運時刻：20:40</span></div>
        <button className="primary-button compact" onClick={onClose}>收下指引</button>
      </section>
    </div>
  )
}

const tarotTopics = [
  { id: '財運', icon: 'coin', english: 'WEALTH', detail: '金錢與機會' },
  { id: '桃花', icon: 'heart', english: 'LOVE', detail: '緣分與關係' },
  { id: '當日運勢', icon: 'sparkle', english: 'TODAY', detail: '今日整體能量' },
]

const tarotPlaceholders = {
  財運: '例如：最近適合做新的財務決定嗎？',
  桃花: '例如：近期會遇見適合的人嗎？',
  當日運勢: '例如：今天最需要留意什麼？',
}

function AskScreen() {
  const [topic, setTopic] = useState('')
  const [question, setQuestion] = useState('')
  const [reading, setReading] = useState(null)
  const canAsk = Boolean(topic)
  const activeReadingStyle = reading ? (readingStarStyleByCard[reading.card] || readingStarStyleByCard.default) : readingStarStyleByCard.default

  const submit = () => {
    if (!canAsk) return
    setReading(readings[topic])
  }

  if (reading) {
    return (
      <main className="screen reading-screen">
        <StatusBar />
        <AppHeader title="宇宙的回信" back={() => setReading(null)} />
        <section className="reading-body">
          <figure className="reading-card">
            <img src={activeReadingStyle.image} alt={`${activeReadingStyle.name}樣式的幸運星`} />
            <figcaption>{reading.card}</figcaption>
          </figure>
          <p className="reading-topic">{topic}・YOUR READING</p>
          <p className="question-echo">「{question.trim() || `${topic}此刻最需要知道的訊息`}」</p>
          <h2>{reading.answer}</h2>
          <p>{reading.detail}</p>
          <div className="reading-note">這次的訊息來自塔羅牌義、今日星象與你的問題關鍵字。</div>
          <button className="primary-button compact" onClick={() => setReading(null)}>再問一件事</button>
        </section>
      </main>
    )
  }

  return (
    <main className="screen ask-screen">
      <StatusBar />
      <AppHeader title="問問宇宙" />
      <section className="ask-body">
        <div className="ask-orb" aria-hidden="true"><Icon name="sparkle" size={40}/></div>
        <h2>今天想問哪一種運勢？</h2>
        <p>先選擇一個主題，讓宇宙為你抽出此刻最需要的牌。</p>
        <div className="topic-row" aria-label="塔羅主題">
          {tarotTopics.map((item) => (
            <button key={item.id} className={topic === item.id ? 'selected' : ''} onClick={() => setTopic(item.id)} aria-pressed={topic === item.id}>
              <span className="topic-icon"><Icon name={item.icon} size={20} filled={item.icon === 'heart'}/></span>
              <strong>{item.id}</strong>
              <small>{item.english}</small>
              <em>{item.detail}</em>
            </button>
          ))}
        </div>
        <label className="question-box">
          <span className="question-label">想問得更具體嗎？<small>選填</small></span>
          <textarea value={question} maxLength={80} onChange={(event) => setQuestion(event.target.value)} placeholder={topic ? tarotPlaceholders[topic] : '請先選擇上方的塔羅主題'} disabled={!topic} />
          <span>{question.length}/80</span>
        </label>
        <button className="primary-button ask-submit" disabled={!canAsk} onClick={submit}><Icon name="sparkle" size={20}/> {topic ? `抽取「${topic}」牌` : '選擇主題後抽牌'}</button>
        <p className="entertainment-note">內容僅供娛樂與自我探索，不代替專業建議。</p>
      </section>
    </main>
  )
}

function ProfileScreen({ onSettings, onEditProfile, profile }) {
  const displayName = profile?.name || '旅行者'
  const zodiac = profile?.zodiac || '等待相遇'
  return (
    <main className="screen profile-screen">
      <StatusBar />
      <AppHeader title="我的宇宙" onSettings={onSettings}/>
      <section className="profile-body">
        <div className="avatar"><img src={luckyStarSleep} alt="戴著睡帽的幸運星" /></div>
        <h2>{zodiac}的 {displayName}</h2>
        <p>{profile ? `太陽${zodiac}・出生資料已建立` : '完成出生資料，打開你的個人運勢'}</p>
        <div className="streak"><span>連續相遇</span><strong>7 天</strong><small>每天留一分鐘給自己</small></div>
        <button className="profile-row" onClick={onEditProfile}><span>我的出生資料</span><Icon name="chevron" size={18}/></button>
        <button className="profile-row"><span>收藏的指引</span><strong>12</strong><Icon name="chevron" size={18}/></button>
        <button className="profile-row" onClick={onSettings}><span>通知與偏好</span><Icon name="chevron" size={18}/></button>
      </section>
    </main>
  )
}

function WechatLoginScreen({ onLogin }) {
  const [agreed, setAgreed] = useState(true)

  return (
    <main className="wechat-login-screen">
      <StatusBar />
      <div className="login-stars" aria-hidden="true"><i/><i/><i/><i/><i/><i/></div>
      <section className="login-brand">
        <h1>星伴</h1>
        <p>和重要的人，一起养一颗星</p>
      </section>
      <section className="login-pet-stage" aria-label="欢迎来到星伴">
        <div className="login-orbit" aria-hidden="true" />
        <img src={luckyStarWave} alt="发光的星星宠物向你招手" />
      </section>
      <section className="login-actions">
        <p>登录后，邀请微信好友<br/>住进同一个星球</p>
        <button className="wechat-login-button" disabled={!agreed} onClick={onLogin}>
          <Icon name="wechat" size={27}/><span>微信一键登录</span>
        </button>
        <label className="login-consent">
          <input type="checkbox" checked={agreed} onChange={(event) => setAgreed(event.target.checked)} />
          <span>我已阅读并同意《用户协议》与《隐私政策》</span>
        </label>
        <small>当前为产品原型，点击后使用模拟微信身份进入</small>
      </section>
    </main>
  )
}

function FriendAvatar({ friend, me = false }) {
  const initial = me ? '我' : friend.name.slice(0, 1)
  return (
    <div className={`friend-avatar ${friend.color || 'rose'}`}>
      <span aria-hidden="true">{initial}</span>
      <small>{me ? '我' : friend.name}</small>
    </div>
  )
}

function InviteFriendsSheet({ existingIds, onClose, onInvite }) {
  const available = demoWechatFriends.filter((friend) => !existingIds.includes(friend.id))
  const [selectedId, setSelectedId] = useState(available[0]?.id || '')
  const [relation, setRelation] = useState('friend')

  return (
    <div className="sheet-backdrop" onMouseDown={onClose}>
      <section className="bottom-sheet invite-sheet" onMouseDown={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="invite-title">
        <div className="sheet-handle" />
        <button className="sheet-close" onClick={onClose} aria-label="关闭"><Icon name="close" size={20}/></button>
        <h2 id="invite-title">邀请朋友一起住</h2>
        <p>选择一位微信好友，再为你们的星球命名关系。</p>

        {available.length ? (
          <div className="wechat-friend-list" aria-label="可邀请的微信好友">
            {available.map((friend) => (
              <button key={friend.id} className={selectedId === friend.id ? 'selected' : ''} onClick={() => setSelectedId(friend.id)} aria-pressed={selectedId === friend.id}>
                <FriendAvatar friend={friend}/><strong>{friend.name}</strong><Icon name={selectedId === friend.id ? 'check' : 'plus'} size={18}/>
              </button>
            ))}
          </div>
        ) : <div className="all-invited">你的演示好友都已经住进来了 ✦</div>}

        <div className="relation-options" aria-label="关系空间">
          <button className={relation === 'friend' ? 'selected' : ''} onClick={() => setRelation('friend')}>
            <span>✨</span><div><strong>星星好友</strong><small>一起养星，互相陪伴</small></div><Icon name="check" size={19}/>
          </button>
          <button disabled><span>🌙</span><div><strong>星星闺蜜</strong><small>亲密闺蜜 · 敬请期待</small></div><Icon name="lock" size={18}/></button>
          <button disabled><span>💫</span><div><strong>星星情侣</strong><small>情侣专属 · 敬请期待</small></div><Icon name="lock" size={18}/></button>
        </div>

        <button className="send-wechat-invite" disabled={!selectedId} onClick={() => onInvite(selectedId, relation)}>
          <Icon name="wechat" size={24}/><span>发送微信邀请</span>
        </button>
        <small className="invite-hint">正式版本将通过微信分享卡片发送邀请链接</small>
      </section>
    </div>
  )
}

function StarSupplySheet({ reason, currentPlan, canCompleteFeedTask, onClose, onSubscribe, onBuyStarPack, onCompleteFeedTask }) {
  const limited = reason === 'limit'
  const feedLimited = reason === 'feed-limit'
  const upgrading = reason === 'upgrade'
  const browsing = reason === 'plans'
  return (
    <div className="sheet-backdrop" onMouseDown={onClose}>
      <section className="bottom-sheet star-supply-sheet" onMouseDown={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="supply-title">
        <div className="sheet-handle" />
        <button className="sheet-close" onClick={onClose} aria-label="關閉"><Icon name="close" size={20}/></button>
        <p className="sheet-kicker">STAR COMPANION</p>
        <div className="supply-mark" aria-hidden="true">✦</div>
        <h2 id="supply-title">{upgrading ? '讓小星住進靈動島' : feedLimited ? '今天的餵食次數已用完' : limited ? '今天的陪伴額度已用完' : browsing ? '選擇你的陪伴方案' : '星糧不夠了'}</h2>
        <p>{upgrading ? '升級 ORBIT PASS，即使離開 App，也能在靈動島看見小星。' : feedLimited ? '完成一次今日任務，或補充 Star 點數，就能再陪小星吃一餐。' : limited ? '選擇適合你的月度方案，讓陪伴繼續。' : browsing ? '從輕量陪伴開始，或解鎖完整的靈動島體驗。' : `每次餵食需要 ${FEED_COST} 星糧，訂閱方案會提供每日補給。`}</p>

        {feedLimited && <button className="feed-task-offer" disabled={!canCompleteFeedTask} onClick={onCompleteFeedTask}><span>✓</span><span className="offer-copy"><strong>{canCompleteFeedTask ? '完成今日星糧任務' : '今日星糧任務已完成'}</strong><small>{canCompleteFeedTask ? '獲得 2 次餵食額度＋20 星糧' : '明天會有新的任務'}</small></span><Icon name={canCompleteFeedTask ? 'chevron' : 'check'} size={18}/></button>}

        {(feedLimited || reason === 'food') && <button className="star-point-offer" onClick={onBuyStarPack}><span>✦</span><span className="offer-copy"><strong>補充 50 Star 點數</strong><small>立即增加 3 次餵食額度</small></span><span className="offer-price"><strong>¥6</strong><small>一次</small></span></button>}

        <button className="starter-pass-offer" disabled={currentPlan !== 'free'} onClick={() => onSubscribe('star')}>
          <span aria-hidden="true">✦</span>
          <span className="offer-copy"><strong>STAR PASS</strong><small>{currentPlan === 'star' ? '目前方案' : '每日 8 次陪伴・每日 10 星糧'}</small></span>
          <span className="offer-price"><strong>¥3</strong><small>/ 月</small></span>
        </button>

        <button className="star-pass-offer orbit-offer" onClick={() => onSubscribe('orbit')}>
          <span className="offer-badge">PREMIUM</span>
          <span className="offer-copy"><strong>ORBIT PASS</strong><small>無限陪伴・每日 20 星糧・寵物常駐靈動島</small></span>
          <span className="offer-price"><strong>¥20</strong><small>/ 月</small></span>
          <span className="dynamic-island-preview" aria-hidden="true"><i>★</i><b>小星陪著你</b></span>
        </button>
        <small className="purchase-note">原型模式：點擊後模擬訂閱成功，不會實際扣款</small>
      </section>
    </div>
  )
}

const petSkins = [
  { id: 'classic', name: '初光', english: 'FIRST LIGHT', image: luckyStarWave, category: '經典' },
  { id: 'aurora', name: '極光夢境', english: 'AURORA REVERIE', image: luckyStarSkinAurora, premium: true, category: '經典' },
  { id: 'eclipse', name: '月蝕玫瑰', english: 'ROSE ECLIPSE', image: luckyStarSkinEclipse, premium: true, category: '經典' },
  { id: 'moonveil', name: '月霧花境', english: 'MOONVEIL BLOOM', image: luckyStarSkinMoonveil, premium: true, category: '經典' },
  { id: 'lunarTide', name: '海月星眠', english: 'LUNAR TIDE', image: luckyStarSkinLunarTide, premium: true, category: '經典' },
  { id: 'azureButterfly', name: '藍蝶星夢', english: 'AZURE BUTTERFLY DREAM', image: luckyStarSkinAzureButterfly, premium: true, category: '經典' },
  { id: 'frostNocturne', name: '冰晶夜曲', english: 'FROST NOCTURNE', image: luckyStarSkinFrostNocturne, premium: true, category: '經典' },
  ...generatedPetSkins,
]

function SkinWardrobeSheet({ currentPlan, petLevel, selectedSkin, onClose, onSelect, onUpgrade }) {
  const canChangeSkin = currentPlan === 'orbit' && petLevel >= 2
  const [activeCategory, setActiveCategory] = useState(() => petSkins.find((skin) => skin.id === selectedSkin)?.category || '全部')
  const visibleSkins = activeCategory === '全部' ? petSkins : petSkins.filter((skin) => skin.category === activeCategory)
  return (
    <div className="sheet-backdrop" onMouseDown={onClose}>
      <section className="bottom-sheet skin-wardrobe-sheet" onMouseDown={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="wardrobe-title">
        <div className="sheet-handle" />
        <button className="sheet-close" onClick={onClose} aria-label="關閉"><Icon name="close" size={20}/></button>
        <p className="sheet-kicker">CELESTIAL ATELIER</p>
        <h2 id="wardrobe-title">星光衣櫥</h2>
        <p>{petLevel < 2 ? '小星升到 Level 2 後，就能換上專屬星空皮膚。' : currentPlan !== 'orbit' ? '稀有皮膚是 ORBIT PASS 專屬收藏。' : '為小星換上今晚最耀眼的模樣。'}</p>

        <div className="skin-category-row" aria-label="皮膚分類">
          {petSkinCategories.map((category) => <button key={category} className={activeCategory === category ? 'active' : ''} onClick={() => setActiveCategory(category)} aria-pressed={activeCategory === category}>{category}</button>)}
        </div>
        <div className="skin-collection-meta"><span>{activeCategory === '全部' ? 'ALL COLLECTIONS' : activeCategory}</span><strong>{visibleSkins.length} STYLES</strong></div>

        <div className="skin-grid" aria-label="星寵皮膚">
          {visibleSkins.map((skin) => {
            const selected = selectedSkin === skin.id
            const locked = skin.premium && !canChangeSkin
            return (
              <button key={skin.id} className={`${selected ? 'selected' : ''} ${locked ? 'locked' : ''}`} disabled={locked && petLevel < 2} onClick={() => locked ? onUpgrade() : onSelect(skin.id)} aria-pressed={selected}>
                <span className="skin-art"><img src={skin.image} alt="" loading="lazy" decoding="async" />{skin.premium && <i>{locked ? 'ORBIT' : 'RARE'}</i>}</span>
                <strong>{skin.name}</strong>
                <small>{skin.english}</small>
                <span className="skin-state">{selected ? '使用中' : locked ? (petLevel < 2 ? 'LEVEL 2' : '解鎖') : '換上'}</span>
              </button>
            )
          })}
        </div>

        {!canChangeSkin && <button className="skin-unlock-cta" disabled={petLevel < 2} onClick={onUpgrade}><span>✦</span><span><strong>{petLevel < 2 ? '尚未達到 Level 2' : '升級 ORBIT PASS・¥20/月'}</strong><small>{petLevel < 2 ? '完成今晚的共同餵食任務即可升級' : '解鎖全部稀有皮膚與靈動島陪伴'}</small></span><Icon name={petLevel < 2 ? 'lock' : 'chevron'} size={18}/></button>}
      </section>
    </div>
  )
}

function StarPetScreen({ onSettings, session }) {
  const [planet, setPlanet] = useState(loadStoredPlanet)
  const [storyTitle, setStoryTitle] = useState('小星今天很開心')
  const [storyBody, setStoryBody] = useState('它剛剛繞著月亮飛了兩圈，現在想安靜地陪你待一會兒。')
  const [celebrating, setCelebrating] = useState(false)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [supplyReason, setSupplyReason] = useState('')
  const [skinOpen, setSkinOpen] = useState(false)
  const [toast, setToast] = useState('')
  const celebrationTimerRef = useRef(null)

  const friends = demoWechatFriends.filter((friend) => planet.friendIds.includes(friend.id))
  const stardust = planet.stardust
  const subscriptionPlan = planet.subscriptionPlan || 'free'
  const hasOrbitPass = subscriptionPlan === 'orbit'
  const dailyPetLimit = subscriptionPlan === 'star' ? STAR_PASS_DAILY_LIMIT : DAILY_PET_LIMIT
  const petRemaining = Math.max(0, dailyPetLimit - planet.petCountToday)
  const dailyFeedAllowance = subscriptionPlan === 'star' ? STAR_PASS_DAILY_LIMIT : DAILY_PET_LIMIT
  const baseFeedRemaining = Math.max(0, dailyFeedAllowance - (planet.dailyFeedCount || 0))
  const bonusFeedCredits = planet.bonusFeedCredits || 0
  const feedRemaining = hasOrbitPass ? Infinity : baseFeedRemaining + bonusFeedCredits
  const activeSkin = petSkins.find((skin) => skin.id === planet.selectedSkin) || petSkins[0]
  const petImage = activeSkin.id === 'classic' && celebrating ? luckyStarCelebrateGif : activeSkin.image

  useEffect(() => {
    try {
      window.localStorage.setItem(PET_PLANET_STORAGE_KEY, JSON.stringify(planet))
    } catch {
      // Keep the shared planet working for the current session.
    }
  }, [planet])

  useEffect(() => () => window.clearTimeout(celebrationTimerRef.current), [])

  const celebrateBriefly = () => {
    setCelebrating(true)
    window.clearTimeout(celebrationTimerRef.current)
    celebrationTimerRef.current = window.setTimeout(() => setCelebrating(false), 1450)
  }

  const interact = (type) => {
    if (type === 'feed') {
      if (!hasOrbitPass && feedRemaining <= 0) {
        setSupplyReason('feed-limit')
        return
      }
      if (planet.stardust < FEED_COST) {
        setSupplyReason('food')
        return
      }
      celebrateBriefly()
      const completesTask = !planet.taskDone && planet.feedCount + 1 >= 3
      setPlanet((current) => ({
        ...current,
        stardust: Math.max(0, current.stardust - FEED_COST + (completesTask ? 10 : 0)),
        feedCount: Math.min(3, current.feedCount + 1),
        dailyFeedCount: hasOrbitPass ? (current.dailyFeedCount || 0) : Math.min(dailyFeedAllowance, (current.dailyFeedCount || 0) + 1),
        bonusFeedCredits: hasOrbitPass || (current.dailyFeedCount || 0) < dailyFeedAllowance ? (current.bonusFeedCredits || 0) : Math.max(0, (current.bonusFeedCredits || 0) - 1),
        taskDone: current.feedCount + 1 >= 3,
        petLevel: completesTask ? Math.max(2, current.petLevel || 1) : (current.petLevel || 1),
        activity: completesTask ? `${session.name}和小星完成了今晚的約定` : `${session.name}剛剛餵了小星`,
      }))
      setStoryTitle(completesTask ? '今晚的星星收好了' : '小星吃得很滿足')
      setStoryBody(completesTask ? '你們一起完成了今天的約定。明天再來看看它吧。' : `這次消耗了 ${FEED_COST} 星糧，小星的心情變好了。`)
      return
    }
    if (!hasOrbitPass && petRemaining <= 0) {
      setSupplyReason('limit')
      return
    }
    celebrateBriefly()
    setStoryTitle('它記得你的手心')
    setStoryBody('小星輕輕靠過來，像是在說：今天也辛苦了。')
    setPlanet((current) => ({ ...current, petCountToday: current.petCountToday + 1, activity: `${session.name}剛剛陪了陪小星` }))
  }

  const completeTask = () => {
    if (planet.taskDone) return
    interact('feed')
  }

  const completeFeedTask = () => {
    if (planet.starTaskClaimed) return
    setPlanet((current) => ({ ...current, starTaskClaimed: true, bonusFeedCredits: (current.bonusFeedCredits || 0) + 2, stardust: Math.min(200, current.stardust + 20), activity: `${session.name}完成星糧任務，帶回了補給` }))
    setSupplyReason('')
    setToast('星糧任務完成・獲得 2 次餵食額度與 20 Star 點數')
    window.setTimeout(() => setToast(''), 2600)
  }

  const buyStarPack = () => {
    setPlanet((current) => ({ ...current, bonusFeedCredits: (current.bonusFeedCredits || 0) + 3, stardust: Math.min(200, current.stardust + 50), activity: `${session.name}補充了 Star 點數，準備繼續照顧小星` }))
    setSupplyReason('')
    setToast('Star 點數已補充・新增 3 次餵食額度')
    window.setTimeout(() => setToast(''), 2600)
  }

  const inviteFriend = (friendId) => {
    const friend = demoWechatFriends.find((item) => item.id === friendId)
    if (!friend) return
    setPlanet((current) => ({ ...current, friendIds: [...new Set([...current.friendIds, friendId])], activity: `${friend.name}接受邀请，住进了这颗星球` }))
    setInviteOpen(false)
    setToast(`已向 ${friend.name} 发送微信邀请`)
    window.setTimeout(() => setToast(''), 2300)
  }

  const subscribe = (plan) => {
    const isOrbit = plan === 'orbit'
    setPlanet((current) => ({ ...current, subscriptionPlan: plan, isStarPassMember: isOrbit, stardust: Math.min(200, current.stardust + (isOrbit ? 100 : 30)) }))
    setSupplyReason('')
    setToast(isOrbit ? 'ORBIT PASS 已開通・靈動島陪伴已解鎖' : 'STAR PASS 已開通・每日可陪伴 8 次')
    window.setTimeout(() => setToast(''), 2300)
  }

  const selectSkin = (skinId) => {
    const skin = petSkins.find((item) => item.id === skinId)
    if (!skin) return
    setPlanet((current) => ({ ...current, selectedSkin: skinId }))
    setToast(`已換上「${skin.name}」皮膚`)
    window.setTimeout(() => setToast(''), 2300)
  }

  const openOrbitUpgrade = () => {
    setSkinOpen(false)
    setSupplyReason('upgrade')
  }

  return (
    <main className="screen pet-screen">
      <StatusBar />
      <AppHeader title="我們的星球" onSettings={onSettings} />

      <section className="planet-members" aria-label="共同居住的好友">
        <div className="planet-company">
          <div className="planet-member-stack">
            <FriendAvatar me friend={{ name: session.name, color: 'rose' }}/>
            {friends.map((friend) => <FriendAvatar key={friend.id} friend={friend}/>)}
          </div>
          <p>{friends.length ? `你和${friends.map((friend) => friend.name).join('、')}一起住在這裡` : '這顆星球正在等待新朋友'}</p>
        </div>
        <button className="invite-friend" onClick={() => setInviteOpen(true)}><Icon name="plus" size={18}/><span>邀請朋友</span></button>
      </section>

      <section className="pet-habitat" aria-label="小星的星空棲地" style={{ backgroundImage: `url(${starPetHabitat})` }}>
        <img className={`star-pet ${celebrating ? 'celebrating' : ''} skin-${activeSkin.id}`} src={petImage} alt={`穿著${activeSkin.name}皮膚、在星空中漂浮的小星`} />
      </section>

      <section className="pet-companion" aria-label="星寵狀態與互動">
        <header className="pet-story" aria-live="polite">
          <p className="pet-day">8月29日・星期六</p>
          <h2>{storyTitle}</h2>
          <p>{storyBody}</p>
        </header>

        <div className="pet-latest"><Icon name="food" size={16}/><span>{planet.activity}</span></div>

        <div className="pet-growth">
          <div className="pet-growth-label"><span>星糧餘額</span><span><strong>{stardust}</strong><small> 顆</small></span></div>
          <div className="stardust-track" role="progressbar" aria-label="星糧餘額" aria-valuemin="0" aria-valuemax="200" aria-valuenow={stardust}>
            <i style={{ width: `${Math.min(100, stardust / 2)}%` }} />
          </div>
          <p>{hasOrbitPass ? 'ORBIT PASS 享有無限餵食・每次消耗 10 Star 點數' : `今日可餵食 ${feedRemaining} 次・用完可做任務或補充 Star 點數`}</p>
        </div>

        <div className="pet-care-actions">
          <button className="pet-primary-action" onClick={() => interact('pet')}><Icon name="heart" size={19} filled />陪伴 · {hasOrbitPass ? '無限' : `${petRemaining}/${dailyPetLimit}`}</button>
          <button className={`pet-secondary-action ${feedRemaining <= 0 ? 'exhausted' : ''}`} onClick={() => interact('feed')}><Icon name={feedRemaining <= 0 ? 'sparkle' : 'food'} size={18} />{feedRemaining <= 0 ? '補充餵食' : `餵食 · −${FEED_COST}`}</button>
        </div>
        <button className={`feed-credit-task ${planet.starTaskClaimed ? 'done' : ''}`} onClick={completeFeedTask} disabled={planet.starTaskClaimed}><span className="feed-credit-task-icon">{planet.starTaskClaimed ? <Icon name="check" size={17}/> : '✦'}</span><span><small>今日星糧任務</small><strong>{planet.starTaskClaimed ? '明天再來領新的星糧' : '完成任務，換取餵食額度'}</strong></span><em>{planet.starTaskClaimed ? '已領取' : '+2 次・+20'}</em><Icon name={planet.starTaskClaimed ? 'check' : 'chevron'} size={17}/></button>
        <button className="star-pass-entry" disabled={hasOrbitPass} onClick={() => setSupplyReason(subscriptionPlan === 'star' ? 'upgrade' : 'plans')}><span>✦</span><span><strong>{hasOrbitPass ? 'ORBIT PASS 已啟用' : subscriptionPlan === 'star' ? '升級 ORBIT PASS' : '查看訂閱方案'}</strong><small>{hasOrbitPass ? '靈動島陪伴已解鎖' : subscriptionPlan === 'star' ? '讓小星住進靈動島' : '¥3 入門・¥20 靈動島陪伴'}</small></span><Icon name={hasOrbitPass ? 'check' : 'chevron'} size={17}/></button>
        <button className="skin-entry" onClick={() => setSkinOpen(true)}><span className={`skin-entry-preview skin-${activeSkin.id}`}><img src={activeSkin.image} alt="" /></span><span><strong>星光衣櫥</strong><small>LEVEL {planet.petLevel}・{activeSkin.name}</small></span><span className="skin-entry-status">{hasOrbitPass && planet.petLevel >= 2 ? '更換' : 'ORBIT'}</span><Icon name={hasOrbitPass && planet.petLevel >= 2 ? 'chevron' : 'lock'} size={17}/></button>

        <button className={`pet-ritual ${planet.taskDone ? 'done' : ''}`} onClick={completeTask} aria-pressed={planet.taskDone}>
          <span className="pet-ritual-copy"><small>今晚的約定</small><strong>一起餵小星 3 次</strong><span>{planet.feedCount}/3</span></span>
          <span className="pet-ritual-reward">{planet.taskDone ? '已完成' : '+10 星糧'}</span>
          <Icon name={planet.taskDone ? 'check' : 'chevron'} size={18} />
        </button>
      </section>
      {inviteOpen && <InviteFriendsSheet existingIds={planet.friendIds} onClose={() => setInviteOpen(false)} onInvite={inviteFriend}/>}
      {supplyReason && <StarSupplySheet reason={supplyReason} currentPlan={subscriptionPlan} canCompleteFeedTask={!planet.starTaskClaimed} onClose={() => setSupplyReason('')} onSubscribe={subscribe} onBuyStarPack={buyStarPack} onCompleteFeedTask={completeFeedTask}/>}
      {skinOpen && <SkinWardrobeSheet currentPlan={subscriptionPlan} petLevel={planet.petLevel} selectedSkin={activeSkin.id} onClose={() => setSkinOpen(false)} onSelect={selectSkin} onUpgrade={openOrbitUpgrade}/>}
      {toast && <div className="pet-toast" role="status">{toast}</div>}
    </main>
  )
}

const homeTasks = [
  { id: 'fortune', icon: '✦', title: '看一眼今日運勢', detail: '替今天留下一點指引' },
  { id: 'companion', icon: '♡', title: '陪小星待一會兒', detail: '和小星完成一次互動' },
  { id: 'wish', icon: '☾', title: '寫下一個小願望', detail: '讓宇宙知道你的心意' },
]

function LittleHomeScreen({ onSettings, session }) {
  const [home, setHome] = useState(loadStoredHome)
  const [toast, setToast] = useState('')
  const [stargazing, setStargazing] = useState(false)
  const stargazingTimerRef = useRef(null)
  const completed = home.taskIds.length
  const allDone = completed === homeTasks.length
  const nextFurniture = homeFurniture.find((item) => !home.owned.includes(item.id))
  const placedItems = homeFurniture.filter((item) => home.placed.includes(item.id))

  useEffect(() => {
    try { window.localStorage.setItem(HOME_STORAGE_KEY, JSON.stringify(home)) } catch { /* Keep the room available for this session. */ }
  }, [home])

  useEffect(() => () => window.clearTimeout(stargazingTimerRef.current), [])

  const showToast = (message) => {
    setToast(message)
    window.setTimeout(() => setToast(''), 2200)
  }

  const toggleTask = (id) => {
    if (home.claimedToday) return
    setHome((current) => ({
      ...current,
      taskIds: current.taskIds.includes(id) ? current.taskIds.filter((item) => item !== id) : [...current.taskIds, id],
    }))
  }

  const claimFurniture = () => {
    if (!allDone || home.claimedToday || !nextFurniture) return
    setHome((current) => ({ ...current, claimedToday: true, owned: [...current.owned, nextFurniture.id], placed: [...current.placed, nextFurniture.id] }))
    showToast(`「${nextFurniture.name}」已放進小家園`)
  }

  const toggleFurniture = (id) => {
    if (!home.owned.includes(id)) return
    setHome((current) => ({
      ...current,
      placed: current.placed.includes(id) ? current.placed.filter((item) => item !== id) : [...current.placed, id],
    }))
  }

  const startStargazing = (event) => {
    event?.currentTarget?.blur?.()
    setStargazing(true)
    window.clearTimeout(stargazingTimerRef.current)
    stargazingTimerRef.current = window.setTimeout(() => setStargazing(false), 2600)
    showToast('小星發現了一顆正在眨眼的星星')
  }

  return (
    <main className="screen home-screen">
      <StatusBar />
      <AppHeader title="小家園" onSettings={onSettings} />
      <section className={`home-scene garden-scene ${stargazing ? 'stargazing' : ''}`} aria-label={`${session.name}的星空花園`} style={{ backgroundImage: `url(${celestialGarden})` }}>
        <div className="home-scene-wash" aria-hidden="true" />
        <div className="garden-sparkles" aria-hidden="true"><i/><i/><i/><i/><i/><i/><i/></div>
        <p className="home-scene-caption">{session.name}的星空花園</p>
        <button className="home-star" onClick={startStargazing} aria-label="和小星一起觀星">
          <img src={luckyStarWave} alt="在花園裡漂浮的小星" />
          <span className="star-tap-hint">點一下</span>
        </button>
        {placedItems.map((item) => <span key={item.id} className={`home-prop home-prop-${item.id} ${item.accent}`} aria-label={item.name}>{item.icon}</span>)}
        <button className="garden-observe" onClick={startStargazing}><Icon name="sparkle" size={15}/><span>{stargazing ? '正在觀星' : '一起觀星'}</span></button>
        <div className="home-scene-copy"><strong>{stargazing ? '星光正在回答你' : '今晚，去花園散步'}</strong><span>{stargazing ? '小星正在許願' : `${placedItems.length} 件家具正在陪著小星`}</span></div>
      </section>

      <section className="home-content">
        <div className="home-section-heading"><div><p>今日任務</p><h2>完成任務，領取家具</h2></div><span className={allDone ? 'complete' : ''}>{completed} / {homeTasks.length}</span></div>
        <div className="home-progress" aria-label={`任務進度 ${completed} / ${homeTasks.length}`}><i style={{ width: `${(completed / homeTasks.length) * 100}%` }} /></div>
        <div className="home-task-list">
          {homeTasks.map((task) => {
            const done = home.taskIds.includes(task.id)
            return <button key={task.id} className={`home-task ${done ? 'done' : ''}`} onClick={() => toggleTask(task.id)} aria-pressed={done}>
              <span className="home-task-icon">{done ? <Icon name="check" size={16} /> : task.icon}</span><span><strong>{task.title}</strong><small>{task.detail}</small></span><Icon name={done ? 'check' : 'chevron'} size={17}/>
            </button>
          })}
        </div>
        <button className={`home-claim ${allDone && !home.claimedToday ? 'ready' : ''}`} onClick={claimFurniture} disabled={!allDone || home.claimedToday || !nextFurniture}>
          <span>✦</span>{home.claimedToday ? '今天的家具已領取' : nextFurniture ? `領取 ${nextFurniture.name}` : '家具圖鑑已集滿'}
        </button>

        <div className="home-section-heading inventory-heading"><div><p>家具清單</p><h2>點一下，擺進你的房間</h2></div><span>{home.owned.length} / {homeFurniture.length}</span></div>
        <div className="furniture-rail" aria-label="家具清單">
          {homeFurniture.map((item) => {
            const owned = home.owned.includes(item.id)
            const placed = home.placed.includes(item.id)
            return <button key={item.id} className={`furniture-card ${item.accent} ${owned ? 'owned' : 'locked'} ${placed ? 'placed' : ''}`} onClick={() => toggleFurniture(item.id)} disabled={!owned} aria-pressed={placed}>
              <span className="furniture-art">{owned ? item.icon : <Icon name="lock" size={20} />}</span><strong>{item.name}</strong><small>{placed ? '已擺放' : owned ? '點擊擺放' : '尚未獲得'}</small>
            </button>
          })}
        </div>
      </section>
      {toast && <div className="pet-toast" role="status">{toast}</div>}
    </main>
  )
}

function SettingsSheet({ onClose, profile, onLogout }) {
  const [notifications, setNotifications] = useState(true)
  return (
    <div className="sheet-backdrop" onMouseDown={onClose}>
      <section className="bottom-sheet settings-sheet" onMouseDown={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="設定">
        <div className="sheet-handle" />
        <button className="sheet-close" onClick={onClose} aria-label="關閉"><Icon name="close" size={20}/></button>
        <h2>設定你的運勢</h2>
        <div className="setting-row"><span><Icon name="bell" size={21}/> 每日提醒</span><button className={`toggle ${notifications ? 'on' : ''}`} onClick={() => setNotifications(!notifications)} aria-label="每日提醒" aria-pressed={notifications}><i/></button></div>
        <div className="setting-row"><span>提醒時間</span><strong>08:30</strong></div>
        <div className="setting-row"><span>星座</span><strong>{profile?.zodiac || '尚未設定'}</strong></div>
        <p>這個網頁只用來預覽畫面，資料留在瀏覽器。正式 iOS App 會把已驗證帳號的資料存到星伴帳號服務，讓你換裝置後可以找回。</p>
        {onLogout && <button className="logout-button" onClick={onLogout}>退出微信登录</button>}
      </section>
    </div>
  )
}

const focusOptions = [
  { id: 'love', label: '感情', icon: 'heart' },
  { id: 'work', label: '工作', icon: 'briefcase' },
  { id: 'money', label: '財運', icon: 'coin' },
  { id: 'mood', label: '心情', icon: 'cloud' },
]

function PersonalizeFlow({ initialProfile, onComplete, onClose }) {
  const [step, setStep] = useState(1)
  const [form, setForm] = useState(() => ({
    name: initialProfile?.name || '',
    birthday: initialProfile?.birthday || '',
    birthTime: initialProfile?.birthTime || '',
    birthPlace: initialProfile?.birthPlace || '',
    focuses: initialProfile?.focuses || ['love', 'mood'],
  }))

  const update = (field, value) => setForm((current) => ({ ...current, [field]: value }))
  const toggleFocus = (id) => setForm((current) => ({
    ...current,
    focuses: current.focuses.includes(id)
      ? current.focuses.filter((item) => item !== id)
      : [...current.focuses, id],
  }))
  const canContinue = form.name.trim().length > 0 && Boolean(form.birthday)
  const today = getLocalDayStamp()

  const finish = () => {
    if (form.focuses.length === 0) return
    onComplete({
      ...form,
      name: form.name.trim(),
      birthPlace: form.birthPlace.trim(),
      zodiac: getZodiac(form.birthday),
      updatedAt: new Date().toISOString(),
    })
  }

  return (
    <div className="personalize-layer" role="dialog" aria-modal="true" aria-label="個人化設定">
      <main className="personalize-screen">
        <StatusBar />
        <header className="setup-header">
          {step === 2 ? <button className="icon-button" onClick={() => setStep(1)} aria-label="上一步"><Icon name="back"/></button> : <span className="header-spacer"/>}
          <div><h1>{step === 1 ? '認識你的宇宙' : '補上出生線索'}</h1><div className="setup-progress"><i className={step >= 1 ? 'active' : ''}/><span/><i className={step === 2 ? 'active' : ''}/></div><p>{step} / 2</p></div>
          {onClose ? <button className="icon-button" onClick={onClose} aria-label="關閉"><Icon name="close"/></button> : <span className="header-spacer"/>}
        </header>

        <form className="setup-form" onSubmit={(event) => { event.preventDefault(); step === 1 ? setStep(2) : finish() }}>
          <div className="setup-scroll">
            <img className="setup-ip" src={luckyStarWave} alt="向你打招呼的幸運星" />
            <div className="setup-copy">
              <h2>{step === 1 ? '先告訴我，怎麼稱呼你' : '讓我更了解你'}</h2>
              <p>{step === 1 ? '這樣我才能陪你走對的運勢旅程' : '可略過，越完整越準確喔'}</p>
            </div>

            {step === 1 ? (
              <div className="setup-fields">
                <label className="setup-field">
                  <span>你的稱呼 <small>必填</small></span>
                  <div><Icon name="profile" size={21}/><input value={form.name} onChange={(event) => update('name', event.target.value)} maxLength={24} placeholder="請輸入你的稱呼" autoComplete="name" /></div>
                </label>
                <label className="setup-field">
                  <span>出生日期 <small>必填</small></span>
                  <div><Icon name="calendar" size={21}/><input type="date" value={form.birthday} min="1900-01-01" max={today} onInput={(event) => update('birthday', event.currentTarget.value)} /></div>
                </label>
              </div>
            ) : (
              <div className="setup-fields">
                <label className="setup-field">
                  <span>出生時間 <small>選填</small></span>
                  <div><Icon name="clock" size={21}/><input type="time" value={form.birthTime} onInput={(event) => update('birthTime', event.currentTarget.value)} /></div>
                </label>
                <label className="setup-field">
                  <span>出生地點 <small>選填</small></span>
                  <div><Icon name="location" size={21}/><input value={form.birthPlace} onChange={(event) => update('birthPlace', event.target.value)} maxLength={40} placeholder="例如：台北" /></div>
                </label>
                <fieldset className="focus-fieldset">
                  <legend>想了解的主題 <small>至少選一個</small></legend>
                  <div className="focus-grid">
                    {focusOptions.map((item) => <button type="button" key={item.id} className={form.focuses.includes(item.id) ? 'selected' : ''} onClick={() => toggleFocus(item.id)} aria-pressed={form.focuses.includes(item.id)}><Icon name={item.icon} size={19} filled={item.icon === 'heart'}/>{item.label}</button>)}
                  </div>
                </fieldset>
              </div>
            )}

            <div className="privacy-note"><Icon name="lock" size={22}/><span>這個網頁原型不會上傳資料。正式 iOS App 登入後，會把出生資料與使用紀錄存進星伴帳號服務；不出售資料，也不做跨 App 追蹤。</span></div>
          </div>

          <footer className="setup-footer">
            <button className="primary-button" type="submit" disabled={step === 1 ? !canContinue : form.focuses.length === 0}>
              <Icon name="sparkle" size={21}/><span>{step === 1 ? '下一步' : '建立我的運勢'}</span><Icon name="chevron" size={21}/>
            </button>
          </footer>
        </form>
      </main>
    </div>
  )
}

const tabs = [
  { id: 'today', label: '今日', icon: 'today' },
  { id: 'ask', label: '问问', icon: 'ask' },
  { id: 'pet', label: '星宠', icon: 'pet' },
  { id: 'home', label: '家園', icon: 'home' },
  { id: 'profile', label: '我的', icon: 'profile' },
]

function TabBar({ active, onChange }) {
  return (
    <nav className="tab-bar" aria-label="主要分頁">
      {tabs.map((tab) => (
        <button key={tab.id} className={active === tab.id ? 'active' : ''} onClick={() => onChange(tab.id)} aria-current={active === tab.id ? 'page' : undefined}>
          <Icon name={tab.icon} size={25}/><span>{tab.label}</span>
        </button>
      ))}
    </nav>
  )
}

export default function App() {
  const [tab, setTab] = useState('pet')
  const [wechatSession, setWechatSession] = useState(loadStoredWechatSession)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [profile, setProfile] = useState(loadStoredProfile)
  const [profileFlowOpen, setProfileFlowOpen] = useState(() => typeof window !== 'undefined' && new URLSearchParams(window.location.search).get('onboarding') === '1')
  const [gatePhase, setGatePhase] = useState(() => shouldShowDailyGate() ? 'closed' : 'done')
  const gateTimerRef = useRef(null)

  useEffect(() => () => window.clearTimeout(gateTimerRef.current), [])

  const openDailyGate = () => {
    if (gatePhase !== 'closed') return
    try {
      window.localStorage.setItem(DAILY_GATE_STORAGE_KEY, getLocalDayStamp())
    } catch {
      // The ritual still works when private browsing blocks storage.
    }
    setGatePhase('opening')
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    gateTimerRef.current = window.setTimeout(() => setGatePhase('done'), reducedMotion ? 120 : 2450)
  }

  const content = useMemo(() => {
    if (tab === 'ask') return <AskScreen />
    if (tab === 'pet') return <StarPetScreen session={wechatSession} onSettings={() => setSettingsOpen(true)} />
    if (tab === 'home') return <LittleHomeScreen session={wechatSession} onSettings={() => setSettingsOpen(true)} />
    if (tab === 'profile') return <ProfileScreen profile={profile} onEditProfile={() => setProfileFlowOpen(true)} onSettings={() => setSettingsOpen(true)} />
    return <TodayScreen profile={profile} onAsk={() => setTab('ask')} onSettings={() => setSettingsOpen(true)} />
  }, [profile, tab, wechatSession])

  const loginWithWechat = () => {
    const session = { id: 'wechat-demo-user', name: '星河', avatar: '⭐', loggedInAt: new Date().toISOString() }
    setWechatSession(session)
    setGatePhase('done')
    setTab('pet')
    try {
      window.localStorage.setItem(WECHAT_SESSION_STORAGE_KEY, JSON.stringify(session))
    } catch {
      // Keep the simulated login for the current session.
    }
  }

  const logoutWechat = () => {
    setWechatSession(null)
    setSettingsOpen(false)
    try {
      window.localStorage.removeItem(WECHAT_SESSION_STORAGE_KEY)
    } catch {
      // The in-memory session is still cleared.
    }
  }

  const saveProfile = (nextProfile) => {
    setProfile(nextProfile)
    setProfileFlowOpen(false)
    try {
      window.localStorage.setItem(PROFILE_STORAGE_KEY, JSON.stringify(nextProfile))
    } catch {
      // Keep the current-session profile when storage is unavailable.
    }
  }

  if (!wechatSession) {
    return <div className="app-shell"><WechatLoginScreen onLogin={loginWithWechat}/></div>
  }

  if (gatePhase !== 'done') {
    return (
      <div className="app-shell">
        <DailyGate phase={gatePhase} onOpen={openDailyGate} />
      </div>
    )
  }

  return (
    <div className="app-shell">
      {profileFlowOpen ? (
        <PersonalizeFlow initialProfile={profile} onComplete={saveProfile} onClose={profile ? () => setProfileFlowOpen(false) : null} />
      ) : (
        <>
          {content}
          <TabBar active={tab} onChange={setTab} />
          {settingsOpen && <SettingsSheet profile={profile} onLogout={logoutWechat} onClose={() => setSettingsOpen(false)} />}
        </>
      )}
    </div>
  )
}
