const paths = {
  settings: <><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.86 2.86-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.4 1.1V21h-4v-.1A1.7 1.7 0 0 0 8.6 19.4a1.7 1.7 0 0 0-1.88.34l-.06.06-2.86-2.86.06-.06A1.7 1.7 0 0 0 4.2 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.4H2.4v-4h.1A1.7 1.7 0 0 0 4 8.6a1.7 1.7 0 0 0-.34-1.88l-.06-.06L6.46 3.8l.06.06A1.7 1.7 0 0 0 8.4 4.2a1.7 1.7 0 0 0 1-.6A1.7 1.7 0 0 0 9.8 2.5V2.4h4v.1A1.7 1.7 0 0 0 14.8 4a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.86 2.86-.06.06A1.7 1.7 0 0 0 19.2 8.4a1.7 1.7 0 0 0 .6 1 1.7 1.7 0 0 0 1.1.4h.1v4h-.1a1.7 1.7 0 0 0-1.5 1.2Z"/></>,
  sparkle: <><path d="M12 2 14 9l7 3-7 3-2 7-2-7-7-3 7-3 2-7Z"/><path d="m5 3 .7 2.3L8 6l-2.3.7L5 9l-.7-2.3L2 6l2.3-.7L5 3Z"/></>,
  heart: <path d="M12 20.5 4.4 13A5.1 5.1 0 0 1 11.6 5.8L12 6.2l.4-.4A5.1 5.1 0 0 1 19.6 13L12 20.5Z"/>,
  briefcase: <><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18M10 12v2h4v-2"/></>,
  coin: <><circle cx="12" cy="12" r="9"/><path d="M9 9.5c0-1 1.1-1.8 3-1.8s3 .8 3 1.8-1 1.7-3 1.7-3 1-3 2 1.1 1.8 3 1.8 3-.8 3-1.8M12 5.5v13"/></>,
  cloud: <path d="M6.3 18h11.5a4.2 4.2 0 0 0 .5-8.3A6.5 6.5 0 0 0 6 8.2 4.9 4.9 0 0 0 6.3 18Z"/>,
  today: <><path d="m12 3 2.2 6.8L21 12l-6.8 2.2L12 21l-2.2-6.8L3 12l6.8-2.2L12 3Z"/><path d="m5 2 .5 2L7.5 5l-2 .5L5 7.5l-.5-2-2-1 2-.5L5 2Z"/></>,
  ask: <><circle cx="12" cy="10" r="6"/><path d="M7.5 14.5 5 21l7-3 7 3-2.5-6.5M12 7.5v5M9.5 10h5"/></>,
  pet: <><path d="m12 2.7 2.7 5.5 6.1.9-4.4 4.3 1 6.1-5.4-2.9-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 2.7Z"/><path d="M9.2 11.5h.01M14.8 11.5h.01M10.2 14c.9.8 2.7.8 3.6 0"/></>,
  home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10Z"/><path d="M9 21v-6h6v6M8 10h.01M16 10h.01"/></>,
  profile: <><circle cx="12" cy="8" r="4"/><path d="M4.5 21a7.5 7.5 0 0 1 15 0"/></>,
  chevron: <path d="m9 5 7 7-7 7"/>,
  close: <path d="m6 6 12 12M18 6 6 18"/>,
  back: <path d="m15 18-6-6 6-6"/>,
  bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/></>,
  calendar: <><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4M17 3v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 17.5h.01M12 17.5h.01"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  location: <><path d="M20 10c0 5-8 12-8 12S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></>,
  globe: <><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.7 2.6 4 5.6 4 9s-1.3 6.4-4 9M12 3c-2.7 2.6-4 5.6-4 9s1.3 6.4 4 9"/></>,
  lock: <><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/></>,
  plus: <path d="M12 5v14M5 12h14"/>,
  users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></>,
  food: <><path d="M4 11h16l-1.4 8H5.4L4 11Z"/><path d="M7 11c.4-3 2-5 5-5s4.6 2 5 5M9 6c0-1 .7-2 2-3M14 6c.2-1.1.9-1.8 2-2.3"/></>,
  check: <path d="m5 12 4 4L19 6"/>,
  wechat: <><path d="M10.3 5.2C5.7 5.2 2 8.1 2 11.7c0 2 1.2 3.9 3.2 5.1l-.8 2.5 2.9-1.5c.9.3 2 .5 3 .5 4.6 0 8.3-3 8.3-6.6s-3.7-6.5-8.3-6.5Z"/><path d="M14.8 8.3c4 0 7.2 2.6 7.2 5.8 0 1.8-1 3.4-2.7 4.5l.6 2.2-2.5-1.3c-.8.3-1.7.4-2.6.4-3.9 0-7.1-2.6-7.1-5.8"/><circle cx="7.5" cy="10.5" r=".65" fill="currentColor" stroke="none"/><circle cx="12.7" cy="10.5" r=".65" fill="currentColor" stroke="none"/><circle cx="13" cy="13.7" r=".58" fill="currentColor" stroke="none"/><circle cx="17.5" cy="13.7" r=".58" fill="currentColor" stroke="none"/></>,
}

export function Icon({ name, size = 24, filled = false, className = '' }) {
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {paths[name]}
    </svg>
  )
}
