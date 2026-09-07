const intlRegionNames = typeof Intl !== "undefined" && Intl.DisplayNames
  ? new Intl.DisplayNames(["ru"], { type: "region" })
  : null

export const COUNTRY_CODE_TO_RU: Record<string, string> = {
  US: "США",
  GB: "Великобритания",
  RU: "Россия",
  SU: "СССР",
  FR: "Франция",
  DE: "Германия",
  IT: "Италия",
  ES: "Испания",
  JP: "Япония",
  KR: "Южная Корея",
  KP: "Северная Корея",
  CN: "Китай",
  HK: "Гонконг",
  TW: "Тайвань",
  CA: "Канада",
  AU: "Австралия",
  IN: "Индия",
  TR: "Турция",
  SE: "Швеция",
  NO: "Норвегия",
  DK: "Дания",
  FI: "Финляндия",
  NL: "Нидерланды",
  BE: "Бельгия",
  PL: "Польша",
  CZ: "Чехия",
  AT: "Австрия",
  CH: "Швейцария",
  IE: "Ирландия",
  NZ: "Новая Зеландия",
  ZA: "ЮАР",
  IL: "Израиль",
  UA: "Украина",
  BY: "Беларусь",
  KZ: "Казахстан",
  GE: "Грузия",
  AM: "Армения",
  TH: "Таиланд",
  ID: "Индонезия",
  PH: "Филиппины",
  IS: "Исландия",
  GR: "Греция",
  PT: "Португалия",
  HU: "Венгрия",
  RO: "Румыния",
  BG: "Болгария",
  RS: "Сербия",
  HR: "Хорватия",
  EG: "Египет",
  AE: "ОАЭ",
  SG: "Сингапур",
  MX: "Мексика",
  BR: "Бразилия",
  AR: "Аргентина",
  CL: "Чили",
  CO: "Колумбия",
}

export const ENGLISH_NAME_TO_RU: Record<string, string> = {
  "united states of america": "США",
  "united states": "США",
  "usa": "США",
  "united kingdom": "Великобритания",
  "great britain": "Великобритания",
  "uk": "Великобритания",
  "england": "Великобритания",
  "russia": "Россия",
  "russian federation": "Россия",
  "soviet union": "СССР",
  "ussr": "СССР",
  "france": "Франция",
  "germany": "Германия",
  "italy": "Италия",
  "spain": "Испания",
  "japan": "Япония",
  "south korea": "Южная Корея",
  "korea, republic of": "Южная Корея",
  "republic of korea": "Южная Корея",
  "korea": "Южная Корея",
  "north korea": "Северная Корея",
  "china": "Китай",
  "hong kong": "Гонконг",
  "taiwan": "Тайвань",
  "canada": "Канада",
  "australia": "Австралия",
  "india": "Индия",
  "turkey": "Турция",
  "türkiye": "Турция",
  "sweden": "Швеция",
  "norway": "Норвегия",
  "denmark": "Дания",
  "finland": "Финляндия",
  "netherlands": "Нидерланды",
  "belgium": "Бельгия",
  "poland": "Польша",
  "czech republic": "Чехия",
  "czechia": "Чехия",
  "austria": "Австрия",
  "switzerland": "Швейцария",
  "ireland": "Ирландия",
  "new zealand": "Новая Зеландия",
  "south africa": "ЮАР",
  "israel": "Израиль",
  "ukraine": "Украина",
  "belarus": "Беларусь",
  "kazakhstan": "Казахстан",
  "georgia": "Грузия",
  "armenia": "Армения",
  "thailand": "Таиланд",
  "indonesia": "Индонезия",
  "philippines": "Филиппины",
  "iceland": "Исландия",
  "greece": "Греция",
  "portugal": "Португалия",
  "hungary": "Венгрия",
  "romania": "Румыния",
  "bulgaria": "Болгария",
  "serbia": "Сербия",
  "croatia": "Хорватия",
  "egypt": "Египет",
  "united arab emirates": "ОАЭ",
  "uae": "ОАЭ",
  "singapore": "Сингапур",
  "mexico": "Мексика",
  "brazil": "Бразилия",
  "argentina": "Аргентина",
  "chile": "Чили",
  "colombia": "Колумбия",
}

export const RUSSIAN_COUNTRY_TO_CODE: Record<string, string> = {
  "сша": "US",
  "великобритания": "GB",
  "россия": "RU",
  "ссср": "SU",
  "франция": "FR",
  "германия": "DE",
  "италия": "IT",
  "испания": "ES",
  "япония": "JP",
  "южная корея": "KR",
  "северная корея": "KP",
  "корея": "KR",
  "китай": "CN",
  "гонконг": "HK",
  "тайвань": "TW",
  "канада": "CA",
  "австралия": "AU",
  "индия": "IN",
  "турция": "TR",
  "швеция": "SE",
  "норвегия": "NO",
  "дания": "DK",
  "финляндия": "FI",
  "нидерланды": "NL",
  "бельгия": "BE",
  "польша": "PL",
  "чехия": "CZ",
  "австрия": "AT",
  "швейцария": "CH",
  "ирландия": "IE",
  "новая зеландия": "NZ",
  "юар": "ZA",
  "израиль": "IL",
  "украина": "UA",
  "беларусь": "BY",
  "казахстан": "KZ",
  "таиланд": "TH",
  "мексика": "MX",
  "бразилия": "BR",
  "аргентина": "AR",
  "оаэ": "AE",
}

export function localizeCountry(item: any): string {
  if (!item) return ""
  
  if (typeof item === "object") {
    const code = (item.iso_3166_1 || "").toUpperCase().trim()
    if (code && COUNTRY_CODE_TO_RU[code]) {
      return COUNTRY_CODE_TO_RU[code]
    }
    const name = (item.name || "").toLowerCase().trim()
    if (name && ENGLISH_NAME_TO_RU[name]) {
      return ENGLISH_NAME_TO_RU[name]
    }
    if (code && intlRegionNames) {
      try {
        const localized = intlRegionNames.of(code)
        if (localized) return localized
      } catch {}
    }
    return item.name || code || ""
  }

  const str = String(item).trim()
  const upper = str.toUpperCase()
  if (COUNTRY_CODE_TO_RU[upper]) {
    return COUNTRY_CODE_TO_RU[upper]
  }

  const lower = str.toLowerCase()
  if (ENGLISH_NAME_TO_RU[lower]) {
    return ENGLISH_NAME_TO_RU[lower]
  }

  // If 2-letter uppercase ISO code
  if (upper.length === 2 && intlRegionNames) {
    try {
      const localized = intlRegionNames.of(upper)
      if (localized) return localized
    } catch {}
  }

  return str
}

export function resolveCountryCode(raw: string): string | undefined {
  if (!raw) return undefined
  const cleaned = raw.trim()
  const upper = cleaned.toUpperCase()
  if (upper.length === 2 && COUNTRY_CODE_TO_RU[upper]) {
    return upper
  }
  const lower = cleaned.toLowerCase()
  if (RUSSIAN_COUNTRY_TO_CODE[lower]) {
    return RUSSIAN_COUNTRY_TO_CODE[lower]
  }
  if (ENGLISH_NAME_TO_RU[lower]) {
    const ru = ENGLISH_NAME_TO_RU[lower]
    return RUSSIAN_COUNTRY_TO_CODE[ru.toLowerCase()]
  }
  return undefined
}

export function localizePlaceOfBirth(place: string): string {
  if (!place) return ""
  const parts = place.split(",").map(p => p.trim())
  if (parts.length === 0) return place
  const last = parts[parts.length - 1]
  const localizedLast = localizeCountry(last)
  if (localizedLast && localizedLast !== last) {
    parts[parts.length - 1] = localizedLast
    return parts.join(", ")
  }
  return place
}
