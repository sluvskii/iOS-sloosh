const IMG_API = "https://api.sloosh.workers.dev/api/v1/images"
const PERSON_PLACEHOLDER = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%23636366'%3E%3Cpath d='M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z'/%3E%3C/svg%3E"

const movies = [
  {
    id: "693134",
    title: "Дюна: Часть вторая",
    originalTitle: "Dune: Part Two",
    category: "movie",
    year: 2024,
    countries: ["США"],
    duration: 166,
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
    backdrop: IMG_API + "/backdrops/693134/original",
    ratings: { imdb: 8.6, kp: 8.5 },
    genres: ["Фантастика", "Приключения", "Боевик", "Драма"],
    trending: true,
    description: "Пол Атрейдес объединяется с Чани и фременами, чтобы отомстить заговорщикам, уничтожившим его семью. Столкнувшись с выбором между любовью всей жизни и судьбой вселенной, он пытается предотвратить кошмарное будущее, которое может предвидеть только он.",
    cast: [
      { name: "Тимоти Шаламе", role: "Пол Атрейдес", photo: IMG_API + "/tmdb/w185/BE2sdjpgsa2rNTFa66f7upkaOP.jpg" },
      { name: "Зендея", role: "Чани", photo: PERSON_PLACEHOLDER },
      { name: "Ребекка Фергюсон", role: "Леди Джессика", photo: PERSON_PLACEHOLDER },
      { name: "Хавьер Бардем", role: "Стилгар", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["157336", "335984", "872585"]
  },
  {
    id: "872585",
    title: "Оппенгеймер",
    originalTitle: "Oppenheimer",
    category: "movie",
    year: 2023,
    countries: ["США", "Великобритания"],
    duration: 180,
    ageRating: "18+",
    poster: IMG_API + "/tmdb/w500/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
    backdrop: IMG_API + "/backdrops/872585/original",
    ratings: { imdb: 8.4, kp: 8.2 },
    genres: ["Биография", "Драма", "История"],
    trending: true,
    description: "История жизни американского физика-теоретика Роберта Оппенгеймера, руководителя Манхэттенского проекта, в рамках которого в Лос-Аламосе было создано первое в мире ядерное оружие.",
    cast: [
      { name: "Киллиан Мёрфи", role: "Роберт Оппенгеймер", photo: PERSON_PLACEHOLDER },
      { name: "Эмили Блант", role: "Китти Оппенгеймер", photo: PERSON_PLACEHOLDER },
      { name: "Мэтт Дэймон", role: "Лесли Гровс", photo: PERSON_PLACEHOLDER },
      { name: "Роберт Дауни мл.", role: "Льюис Штраусс", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["157336", "155", "693134"]
  },
  {
    id: "157336",
    title: "Интерстеллар",
    originalTitle: "Interstellar",
    category: "movie",
    year: 2014,
    countries: ["США", "Великобритания"],
    duration: 169,
    ageRating: "12+",
    poster: IMG_API + "/tmdb/w500/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
    backdrop: IMG_API + "/backdrops/157336/original",
    ratings: { imdb: 8.7, kp: 8.6 },
    genres: ["Фантастика", "Драма", "Приключения"],
    trending: true,
    description: "Когда засуха и пыльные бури приводят человечество к продовольственному кризису, коллектив исследователей и учёных отправляется сквозь червоточину в поисках нового дома для человечества.",
    cast: [
      { name: "Мэттью Макконахи", role: "Купер", photo: PERSON_PLACEHOLDER },
      { name: "Энн Хэтэуэй", role: "Амелия Бренд", photo: PERSON_PLACEHOLDER },
      { name: "Джессика Честейн", role: "Мёрф", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["693134", "872585", "335984"]
  },
  {
    id: "414906",
    title: "Бэтмен",
    originalTitle: "The Batman",
    category: "movie",
    year: 2022,
    countries: ["США"],
    duration: 176,
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/74xTEgt7R36Fpooo50r9T25onhq.jpg",
    backdrop: IMG_API + "/backdrops/414906/original",
    ratings: { imdb: 7.8, kp: 7.9 },
    genres: ["Детектив", "Боевик", "Криминал"],
    trending: false,
    description: "Брюс Уэйн на второй год своей борьбы с преступностью расследует серию убийств высокопоставленных лиц Готэма, организованных таинственным Загадочником, раскрывая паутину коррупции города.",
    cast: [
      { name: "Роберт Паттинсон", role: "Брюс Уэйн", photo: PERSON_PLACEHOLDER },
      { name: "Зои Кравиц", role: "Селина Кайл", photo: PERSON_PLACEHOLDER },
      { name: "Пол Дано", role: "Загадочник", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["155", "550", "335984"]
  },
  {
    id: "1396",
    title: "Во все тяжкие",
    originalTitle: "Breaking Bad",
    category: "tv",
    year: 2008,
    countries: ["США"],
    duration: "5 сезонов",
    ageRating: "18+",
    poster: IMG_API + "/tmdb/w500/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
    backdrop: IMG_API + "/backdrops/1396/original",
    ratings: { imdb: 9.5, kp: 8.9 },
    genres: ["Криминал", "Драма", "Триллер"],
    trending: true,
    description: "Школьный учитель химии Уолтер Уайт узнает о неизлечимом заболевании легких. Ради финансового благополучия семьи он решает производить чистейший метамфетамин вместе с бывшим учеником.",
    cast: [
      { name: "Брайан Крэнстон", role: "Уолтер Уайт", photo: PERSON_PLACEHOLDER },
      { name: "Аарон Пол", role: "Джесси Пинкман", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["66732", "550", "278"]
  },
  {
    id: "66732",
    title: "Очень странные дела",
    originalTitle: "Stranger Things",
    category: "tv",
    year: 2016,
    countries: ["США"],
    duration: "4 сезона",
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/49WJfeN0moxb9IPfGn8AIqMGskD.jpg",
    backdrop: IMG_API + "/tmdb/w1280/56v2KjBlU4XaOv9rVYEQypROD7P.jpg",
    ratings: { imdb: 8.7, kp: 8.4 },
    genres: ["Ужасы", "Фантастика", "Драма"],
    trending: true,
    description: "1980-е годы. В тихом провинциальном городке исчезает подросток Уилл. Друзья и семья начинают поиски и сталкиваются с секретными правительственными экспериментами и потусторонними силами.",
    cast: [
      { name: "Милли Бобби Браун", role: "Одиннадцать", photo: PERSON_PLACEHOLDER },
      { name: "Финн Вулфхард", role: "Майк Уилер", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["1396", "569094", "157336"]
  },
  {
    id: "569094",
    title: "Человек-паук: Паутина вселенных",
    originalTitle: "Spider-Man: Across the Spider-Verse",
    category: "cartoon",
    year: 2023,
    countries: ["США"],
    duration: 140,
    ageRating: "12+",
    poster: IMG_API + "/tmdb/w500/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg",
    backdrop: IMG_API + "/backdrops/569094/original",
    ratings: { imdb: 8.7, kp: 8.5 },
    genres: ["Мультфильм", "Боевик", "Приключения"],
    trending: true,
    description: "Майлз Моралес отправляется в путешествие по мультивселенной, где встречает Общество Людей-Пауков, защищающих мироздание. Столкнувшись с угрозой, Майлз вынужден переосмыслить звание героя.",
    cast: [
      { name: "Шамейк Мур", role: "Майлз Моралес", photo: PERSON_PLACEHOLDER },
      { name: "Хейли Стайнфелд", role: "Гвен Стейси", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["129", "693134", "414906"]
  },
  {
    id: "129",
    title: "Унесённые призраками",
    originalTitle: "Sen to Chihiro no kamikakushi",
    category: "anime",
    year: 2001,
    countries: ["Япония"],
    duration: 125,
    ageRating: "12+",
    poster: IMG_API + "/tmdb/w500/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg",
    backdrop: IMG_API + "/backdrops/129/original",
    ratings: { imdb: 8.6, kp: 8.5 },
    genres: ["Аниме", "Мультфильм", "Фэнтези"],
    trending: false,
    description: "Маленькая Тихиро с родителями попадает в таинственный заброшенный город, где хозяйничает ведьма Юбаба. Чтобы расколдовать превращенных в свиней родителей, девочке предстоит преодолеть страх.",
    cast: [
      { name: "Руми Хиираги", role: "Тихиро Огино", photo: PERSON_PLACEHOLDER },
      { name: "Мию Ирино", role: "Хаку", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["569094", "278", "157336"]
  },
  {
    id: "155",
    title: "Тёмный рыцарь",
    originalTitle: "The Dark Knight",
    category: "movie",
    year: 2008,
    countries: ["США", "Великобритания"],
    duration: 152,
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/qJ2tW6WMUDux911r6m7haRef0WH.jpg",
    backdrop: IMG_API + "/backdrops/155/original",
    ratings: { imdb: 9.0, kp: 8.5 },
    genres: ["Боевик", "Криминал", "Драма"],
    trending: true,
    description: "Бэтмен поднимает ставки в войне с криминалом Готэма. С помощью лейтенанта Джима Гордона и прокурора Харви Дента он намерен очистить улицы от преступности, но в городе появляется Джокер.",
    cast: [
      { name: "Кристиан Бэйл", role: "Брюс Уэйн / Бэтмен", photo: PERSON_PLACEHOLDER },
      { name: "Хит Леджер", role: "Джокер", photo: PERSON_PLACEHOLDER },
      { name: "Аарон Экхарт", role: "Харви Дент", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["414906", "550", "872585"]
  },
  {
    id: "550",
    title: "Бойцовский клуб",
    originalTitle: "Fight Club",
    category: "movie",
    year: 1999,
    countries: ["США", "Германия"],
    duration: 139,
    ageRating: "18+",
    poster: IMG_API + "/tmdb/w500/bptfVGEQuv6vDTIMVCHjJ9Dz8PX.jpg",
    backdrop: IMG_API + "/backdrops/550/original",
    ratings: { imdb: 8.8, kp: 8.7 },
    genres: ["Драма", "Триллер"],
    trending: false,
    description: "Терзаемый бессонницей офисный клерк знакомится с харизматичным торговцем мылом Тайлером Дёрденом. Они организуют подпольный бойцовский клуб, привлекающий толпы мужчин.",
    cast: [
      { name: "Эдвард Нортон", role: "Рассказчик", photo: PERSON_PLACEHOLDER },
      { name: "Брэд Питт", role: "Тайлер Дёрден", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["155", "278", "335984"]
  },
  {
    id: "278",
    title: "Побег из Шоушенка",
    originalTitle: "The Shawshank Redemption",
    category: "movie",
    year: 1994,
    countries: ["США"],
    duration: 142,
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/lyQBXzOQSuE59IsHyhrp0qIiPAz.jpg",
    backdrop: IMG_API + "/backdrops/278/original",
    ratings: { imdb: 9.3, kp: 9.1 },
    genres: ["Драма"],
    trending: false,
    description: "Успешный банкир Энди Дюфрейн несправедливо осужден на два пожизненных срока за убийство жены и ее любовника. В суровой тюрьме Шоушенк он не теряет надежду на свободу.",
    cast: [
      { name: "Тим Роббинс", role: "Энди Дюфрейн", photo: PERSON_PLACEHOLDER },
      { name: "Морган Фриман", role: "Эллис Бойд «Ред»", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["550", "155", "872585"]
  },
  {
    id: "335984",
    title: "Бегущий по лезвию 2049",
    originalTitle: "Blade Runner 2049",
    category: "movie",
    year: 2017,
    countries: ["США", "Великобритания"],
    duration: 164,
    ageRating: "16+",
    poster: IMG_API + "/tmdb/w500/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg",
    backdrop: IMG_API + "/backdrops/335984/original",
    ratings: { imdb: 8.0, kp: 7.8 },
    genres: ["Фантастика", "Детектив", "Драма"],
    trending: true,
    description: "Офицер полиции Кей — репликант нового поколения, устраняющий вышедшие из строя старые модели. Во время задания он обнаруживает тайну, способную перевернуть мировой порядок.",
    cast: [
      { name: "Райан Гослинг", role: "Офицер Кей", photo: PERSON_PLACEHOLDER },
      { name: "Харрисон Форд", role: "Рик Декард", photo: PERSON_PLACEHOLDER }
    ],
    similarIds: ["693134", "157336", "414906"]
  }
]

let activeCategory = "all"
let activeFilter = "popular"
let currentMovie = null
let bookmarks = []

try {
  const saved = localStorage.getItem("sloosh_bookmarks")
  if (saved) bookmarks = JSON.parse(saved)
} catch (e) {
  bookmarks = []
}

const screenHome = document.getElementById("screenHome")
const screenSearch = document.getElementById("screenSearch")
const screenBookmarks = document.getElementById("screenBookmarks")
const screenDetails = document.getElementById("screenDetails")
const tabBar = document.getElementById("tabBar")

const homeGrid = document.getElementById("homeGrid")
const categoryTabs = document.getElementById("categoryTabs")
const filterRow = document.getElementById("filterRow")

const searchInput = document.getElementById("searchInput")
const searchClear = document.getElementById("searchClear")
const searchGrid = document.getElementById("searchGrid")
const searchEmptyState = document.getElementById("searchEmptyState")

const bookmarksGrid = document.getElementById("bookmarksGrid")
const bookmarksEmptyState = document.getElementById("bookmarksEmptyState")
const bookmarksCounter = document.getElementById("bookmarksCounter")

const detailsScroll = document.getElementById("detailsScroll")
const detailsBackBtn = document.getElementById("detailsBackBtn")
const detailsTopTitle = document.getElementById("detailsTopTitle")
const detailsFavBtn = document.getElementById("detailsFavBtn")
const detailsFavSvg = document.getElementById("detailsFavSvg")
const detailsBackdrop = document.getElementById("detailsBackdrop")
const detailsTitle = document.getElementById("detailsTitle")
const detailsOrigTitle = document.getElementById("detailsOrigTitle")
const detailsRating = document.getElementById("detailsRating")
const detailsAge = document.getElementById("detailsAge")
const detailsYear = document.getElementById("detailsYear")
const detailsCountry = document.getElementById("detailsCountry")
const detailsDuration = document.getElementById("detailsDuration")
const detailsPlayBtn = document.getElementById("detailsPlayBtn")
const detailsDescription = document.getElementById("detailsDescription")
const detailsGenres = document.getElementById("detailsGenres")
const detailsCast = document.getElementById("detailsCast")
const detailsCastSection = document.getElementById("detailsCastSection")
const detailsSimilar = document.getElementById("detailsSimilar")
const detailsSimilarSection = document.getElementById("detailsSimilarSection")
const similarSectionTitle = document.getElementById("similarSectionTitle")

function getMovieById(id) {
  return movies.find((m) => String(m.id) === String(id))
}

function getRating(movie) {
  return movie.ratings.imdb || movie.ratings.kp || 0
}

function createCard(movie) {
  const rating = getRating(movie)
  const el = document.createElement("div")
  el.className = "movie-card"
  el.innerHTML = `
    <div class="card-poster-wrap">
      <img class="card-poster-img" src="${movie.poster}" alt="${movie.title}" loading="lazy">
      <span class="card-rating-badge">${rating.toFixed(1)}</span>
    </div>
    <div class="card-meta-wrap">
      <span class="card-title">${movie.title}</span>
      <span class="card-subtitle">${movie.year} • ${movie.genres[0] || ""}</span>
    </div>
  `
  el.addEventListener("click", () => openDetails(movie))
  return el
}

function renderHome() {
  homeGrid.innerHTML = ""

  let list = movies.filter((m) => {
    if (activeCategory === "all") return true
    return m.category === activeCategory
  })

  if (activeFilter === "top") {
    list = [...list].sort((a, b) => getRating(b) - getRating(a))
  } else {
    list = [...list].sort((a, b) => (b.trending ? 1 : 0) - (a.trending ? 1 : 0))
  }

  list.forEach((m) => homeGrid.appendChild(createCard(m)))
}

function renderSearch() {
  const query = searchInput.value.trim().toLowerCase()
  searchClear.style.display = query ? "block" : "none"
  searchGrid.innerHTML = ""

  if (!query) {
    searchEmptyState.style.display = "none"
    movies.forEach((m) => searchGrid.appendChild(createCard(m)))
    return
  }

  const results = movies.filter((m) => {
    return (
      m.title.toLowerCase().includes(query) ||
      m.originalTitle.toLowerCase().includes(query) ||
      m.genres.some((g) => g.toLowerCase().includes(query))
    )
  })

  if (results.length === 0) {
    searchEmptyState.style.display = "block"
  } else {
    searchEmptyState.style.display = "none"
    results.forEach((m) => searchGrid.appendChild(createCard(m)))
  }
}

function renderBookmarks() {
  bookmarksGrid.innerHTML = ""
  const favs = movies.filter((m) => bookmarks.includes(String(m.id)))
  bookmarksCounter.textContent = `${favs.length}`

  if (favs.length === 0) {
    bookmarksEmptyState.style.display = "block"
  } else {
    bookmarksEmptyState.style.display = "none"
    favs.forEach((m) => bookmarksGrid.appendChild(createCard(m)))
  }
}

function updateFavIcon() {
  if (!currentMovie) return
  const isFav = bookmarks.includes(String(currentMovie.id))
  if (isFav) {
    detailsFavBtn.classList.add("active")
    detailsFavSvg.innerHTML = '<path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" fill="#ffffff"></path>'
  } else {
    detailsFavBtn.classList.remove("active")
    detailsFavSvg.innerHTML = '<path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path>'
  }
}

function toggleBookmark() {
  if (!currentMovie) return
  const idStr = String(currentMovie.id)
  const idx = bookmarks.indexOf(idStr)
  if (idx > -1) {
    bookmarks.splice(idx, 1)
  } else {
    bookmarks.push(idStr)
  }

  try {
    localStorage.setItem("sloosh_bookmarks", JSON.stringify(bookmarks))
  } catch (e) {}

  updateFavIcon()
  renderBookmarks()
}

function openDetails(movie) {
  currentMovie = movie
  detailsScroll.scrollTop = 0
  detailsTopTitle.classList.remove("visible")

  detailsTopTitle.textContent = movie.title
  detailsBackdrop.src = movie.backdrop
  detailsTitle.textContent = movie.title

  if (movie.originalTitle && movie.originalTitle !== movie.title) {
    detailsOrigTitle.textContent = movie.originalTitle
    detailsOrigTitle.style.display = "block"
  } else {
    detailsOrigTitle.style.display = "none"
  }

  const rating = getRating(movie)
  detailsRating.textContent = rating.toFixed(1)
  detailsAge.textContent = movie.ageRating || ""
  detailsAge.style.display = movie.ageRating ? "inline-block" : "none"
  detailsYear.textContent = `${movie.year}`
  detailsCountry.textContent = movie.countries && movie.countries[0] ? movie.countries[0] : ""
  detailsCountry.style.display = detailsCountry.textContent ? "inline-block" : "none"

  if (typeof movie.duration === "number") {
    detailsDuration.textContent = `${movie.duration} мин`
  } else {
    detailsDuration.textContent = movie.duration || ""
  }
  detailsDuration.style.display = detailsDuration.textContent ? "inline-block" : "none"

  detailsDescription.textContent = movie.description || ""

  detailsGenres.innerHTML = ""
  if (movie.genres && movie.genres.length > 0) {
    movie.genres.forEach((g) => {
      const pill = document.createElement("span")
      pill.className = "genre-pill"
      pill.textContent = g
      detailsGenres.appendChild(pill)
    })
  }

  detailsCast.innerHTML = ""
  if (movie.cast && movie.cast.length > 0) {
    detailsCastSection.style.display = "block"
    movie.cast.forEach((actor) => {
      const item = document.createElement("div")
      item.className = "actor-item"
      item.innerHTML = `
        <img class="actor-photo" src="${actor.photo}" alt="${actor.name}">
        <span class="actor-name">${actor.name}</span>
        <span class="actor-role">${actor.role}</span>
      `
      detailsCast.appendChild(item)
    })
  } else {
    detailsCastSection.style.display = "none"
  }

  detailsSimilar.innerHTML = ""
  if (movie.similarIds && movie.similarIds.length > 0) {
    detailsSimilarSection.style.display = "block"
    similarSectionTitle.textContent = movie.category === "tv" ? "Похожие сериалы" : "Похожие фильмы"
    movie.similarIds.forEach((sId) => {
      const sim = getMovieById(sId)
      if (sim) {
        const card = document.createElement("div")
        card.className = "similar-card"
        card.innerHTML = `
          <div class="card-poster-wrap">
            <img class="card-poster-img" src="${sim.poster}" alt="${sim.title}" loading="lazy">
            <span class="card-rating-badge">${getRating(sim).toFixed(1)}</span>
          </div>
          <div class="card-meta-wrap">
            <span class="card-title">${sim.title}</span>
            <span class="card-subtitle">${sim.year}</span>
          </div>
        `
        card.addEventListener("click", () => openDetails(sim))
        detailsSimilar.appendChild(card)
      }
    })
  } else {
    detailsSimilarSection.style.display = "none"
  }

  updateFavIcon()
  screenDetails.classList.add("active")
  tabBar.classList.add("hidden")

  history.pushState({ screen: "details", id: movie.id }, "")
}

function closeDetails() {
  screenDetails.classList.remove("active")
  tabBar.classList.remove("hidden")
  currentMovie = null
}

function switchTab(tabName) {
  document.querySelectorAll(".tab-button").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tabName)
  })

  screenHome.classList.toggle("active", tabName === "home")
  screenSearch.classList.toggle("active", tabName === "search")
  screenBookmarks.classList.toggle("active", tabName === "bookmarks")

  if (tabName === "search") {
    renderSearch()
    setTimeout(() => searchInput.focus(), 100)
  } else if (tabName === "bookmarks") {
    renderBookmarks()
  }
}

detailsScroll.addEventListener("scroll", () => {
  const isScrolled = detailsScroll.scrollTop > 160
  detailsTopTitle.classList.toggle("visible", isScrolled)
})

detailsBackBtn.addEventListener("click", () => {
  if (history.state && history.state.screen === "details") {
    history.back()
  } else {
    closeDetails()
  }
})

detailsFavBtn.addEventListener("click", toggleBookmark)

detailsPlayBtn.addEventListener("click", () => {
  detailsPlayBtn.style.opacity = "0.7"
  setTimeout(() => (detailsPlayBtn.style.opacity = "1"), 200)
})

categoryTabs.addEventListener("click", (e) => {
  const pill = e.target.closest(".tab-pill")
  if (!pill) return
  document.querySelectorAll(".category-tabs .tab-pill").forEach((p) => p.classList.remove("active"))
  pill.classList.add("active")
  activeCategory = pill.dataset.cat
  renderHome()
})

filterRow.addEventListener("click", (e) => {
  const pill = e.target.closest(".filter-pill")
  if (!pill) return
  document.querySelectorAll(".filter-row .filter-pill").forEach((p) => p.classList.remove("active"))
  pill.classList.add("active")
  activeFilter = pill.dataset.filter
  renderHome()
})

searchInput.addEventListener("input", renderSearch)

searchClear.addEventListener("click", () => {
  searchInput.value = ""
  renderSearch()
  searchInput.focus()
})

tabBar.addEventListener("click", (e) => {
  const btn = e.target.closest(".tab-button")
  if (!btn) return
  switchTab(btn.dataset.tab)
})

window.addEventListener("popstate", (e) => {
  if (!e.state || e.state.screen !== "details") {
    closeDetails()
  }
})

window.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && screenDetails.classList.contains("active")) {
    history.back()
  }
})

renderHome()
renderBookmarks()
