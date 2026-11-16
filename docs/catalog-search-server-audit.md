# Серверный поиск: аудит и статус исправлений

## Как читать этот отчет

Первичный аудит выполнен на `sluvskii/sloosh-api@77665388051de9685632db41c5222e01dbfcacc7`.
Он воспроизводил 15 старых поведений. **Это историческая база, не описание нового сервера.**
Диагностика `tools/search-audit/` намеренно привязана к старому коммиту и проверяет
воспроизводимость старых ошибок; ее зеленый результат НЕ означает корректность поиска.

Исправления реализованы серверным агентом в коммитах `95ee17e` и
[`80b0048661cf2bffc334ba5a7aa85ffa091188ab`](https://github.com/sluvskii/sloosh-api/tree/80b0048661cf2bffc334ba5a7aa85ffa091188ab),
ветка `arena/b3ecf543-sloosh-api`, [draft PR #1](https://github.com/sluvskii/sloosh-api/pull/1).
На момент клиентской интеграции PR открыт и остается черновиком. **«Исправлено на сервере»
ниже означает исправлено в этой ветке, а не «уже выложено в production».**

Прочитаны контракт, обязательные изменения iOS, серверный отчет и соответствующие
тесты. Результаты 80/80 unit/HTTP и 20/20 preview приняты из переданного серверного
отчета; в iOS-сессии они повторно не запускались. Проверки preview используют mock-каталог,
а не живые данные. Production revision и интеграция на устройстве еще не подтверждены.

## Статус каждого из 15 пунктов

Ссылки ниже зафиксированы на серверном коммите `80b0048`.

| № | Историческое наблюдение | Текущий статус, контракт и проверка |
|---|---|---|
| 1 | v1/v2 подключались к одному обработчику | **Исправлено на сервере как единый явный контракт**, а не разделение движков по версии. Алиасы сохранены намеренно. [Контракт](https://github.com/sluvskii/sloosh-api/blob/80b0048/docs/search-contract.md), [http-security: v1==v2](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/http-security.test.ts). |
| 2 | В старой текстовой ветке отсутствовало применение фильтров | **Исправлено на сервере:** тип, диапазоны, AND-жанры, ANY-страны, обогащение. Контракт §3–4; [title-search: type, year/rating, genres, countries](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/title-search.test.ts). |
| 3 | Верхние границы без нижних не включали discover | **Исправлено на сервере.** Контракт §3; [discover: runs discovery for upper-only bounds](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 4 | Ключ кеша не различал yearTo/ratingTo | **Исправлено на сервере:** полный fingerprint запроса. Контракт §6; [contract: все поля ключа](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/contract.test.ts), [discover: never serves one filter set for another](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 5 | Пустая выдача кешировалась около часа | **Исправлено на сервере:** negative TTL 45 с/isolate, CDN s-maxage 30 с; positive 300 с/isolate. Контракт §6; [discover: caches an empty discovery briefly](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts), [HTTP: empty-cache headers](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/http-security.test.ts). Это не измеренная гарантия свежести production. |
| 6 | Studio не входила в поисковый контракт | **Исправлено на сервере:** studio поддержана в discover; `query+studio` явно запрещена 400, а не превращается в поиск названия студии. Контракт §3.2; [discover: applies studio scope per branch](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts), [contract: unsupported combinations](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/contract.test.ts). |
| 7 | Без типа discover запрашивал только фильмы | **Исправлено на сервере:** обе ветки. Контракт §3.1, §5; [discover: queries both branches when no type is selected](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 8 | Скрытые минимумы голосов и ограничение дат мешали новинкам | **Исправлено на сервере:** явные `minVotes` и `release`, без неявного ограничения по дате; для RATING остается необходимый upstream vote floor 1, раскрытый в disclosures. Контракт §3–4, §8; [discover: vote floors, newest, release state](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 9 | Аниме-TV получало movie-даты, жанры и сортировку | **Исправлено на сервере:** построение параметров по ветке. Контракт §3, §5; [discover: TV/movie parameters, mixed anime genre mapping](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). Живые сочетания параметров еще требуют приемки. |
| 10 | Чередование веток не обеспечивало сортировку | **Исправлено на сервере в пределах заявленной области:** детерминированное слияние, typed tie-break/dedup, курсор. После глубины 8 — оконный порядок, не глобальная сортировка всего каталога. Контракт §5, §8; [merge-and-suggestions: total order, page slices](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/merge-and-suggestions.test.ts), [discover: global order, cursors, no overlap](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 11 | Discover удалял карточки без постера | **Исправлено на сервере:** постер не является условием попадания в поиск. Контракт §3, §8; [discover: posterless releases/announcements](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/discover.test.ts). |
| 12 | Title-search удалял анонсы без даты и арта | **Исправлено на сервере.** Контракт §4, §8; [title-search: keeps posterless and undated announcements](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/title-search.test.ts). При явном фильтре даты неизвестная дата остается неизвестной, а не подходящей. |
| 13 | Работы из person.known_for смешивались с title-hits | **Исправлено на сервере:** разворот персон удален из выдачи названий. Контракт §4, §7; [title-search: does not expand person matches](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/title-search.test.ts). Это не отдельная новая функция поиска людей. |
| 14 | Не было своей коррекции и серверных подсказок | **Исправлено на сервере ограниченно:** наблюдаемый словарь, раскладка/транслит/OSA, максимум две альтернативы после успешной пустой первой страницы без фильтров, раскрытие коррекции. Это НЕ полный индекс каталога. Контракт §7–8; [title-search: typo/layout, bounds, no guessing on hits/filters](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/title-search.test.ts), [suggestions: ranking/fallback](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/merge-and-suggestions.test.ts). |
| 15 | Короткой карточки не хватало для проверки страны | **Исправлено на сервере с явным бюджетом:** обогащение ≤8 карточек/страница; три состояния; неизвестные считаются в meta или возвращаются помеченными при opt-in. Контракт §3–4, §8; [title-search: enrichment, unknown metadata vs mismatch](https://github.com/sluvskii/sloosh-api/blob/80b0048/tests/title-search.test.ts). Недостаток данных не считается доказанным совпадением. |

Полный [контракт](https://github.com/sluvskii/sloosh-api/blob/80b0048/docs/search-contract.md),
[обязательные изменения iOS](https://github.com/sluvskii/sloosh-api/blob/80b0048/docs/ios-contract-changes.md),
[отчет проверок](https://github.com/sluvskii/sloosh-api/blob/80b0048/docs/search-verification-report.md),
[машинный preview-отчет](https://github.com/sluvskii/sloosh-api/blob/80b0048/docs/search-verification.preview.json).

## Что делает согласованный iOS-клиент

- Отправляет title-query вместе с допустимыми фильтрами, но не `order`/`studio`.
  Сортировка title-результатов, если выбрана, остается явно локальной.
- Новый сервер владеет правилами фильтрации. Клиент не дублирует их поверх
  versioned-ответа и не удаляет принятый сервером результат из-за пустого `countries`.
  Это также сохраняет расширение FILM/TV_SERIES при явном жанре анимации/аниме:
  допустимая комбинация, НЕ ошибка 400. Для старого ответа без `contractVersion`
  сохранена прежняя консервативная проверка как ограниченная совместимость.
- Сохраняет серверный порядок discover, передает непрозрачный `nextCursor`,
  при ошибке повторяет тот же курсор. `sortScope=window` раскрывается как
  «Сортировка по загруженным результатам». `total_results` не используется как
  общее число совпадений под фильтрами; UI показывает число загруженных карточек.
- Читает `query.raw/resolved/corrected/correction.reason`, не запускает вторую
  локальную коррекцию нового контракта, продолжает страницы по resolved-query.
- Получает серверные подсказки с debounce/отменой/проверкой поколения; при ошибках
  подсказок остается локальная история/наблюденные названия. В UI не раскрываются
  внутренние источники данных.
- Ошибки 400 показываются как ошибка условий запроса, не как пустая выдача;
  ошибки сети/5xx оставляют retry и не запускают коррекцию.
- Авторизация, удаленная конфигурация, artwork identity и воспроизведение не
  заменяются поисковыми заглушками или preview-токенами.

### Незакрытое UX-ограничение исходного запроса

В текущем серверном контракте нет флага отключения автоматической коррекции для
одного запроса. Поэтому клиент показывает исходную строку и причину, но **не
добавляет фиктивную кнопку «искать без исправления»**: повтор `query.raw` в тех же
условиях снова может исправиться. Для работающего override нужен аддитивный
серверный параметр и соответствующие тесты/ключ кеша. Это не блокирует чтение
корректных результатов, но остается отдельным UX-пунктом приемки.

## Обязательная приемка перед production

1. Проверить фактическую серверную revision, preview/prod-пути через региональный
   шлюз и совместимость старого клиента. Серверный PR пока нельзя считать выложенным.
2. Согласовать список **типизированных ID**: точное/оригинальное/альтернативное
   название, перестановка букв, короткие и одноименные названия разных лет,
   одинаковый числовой ID у movie/tv, свежие релизы, анонсы, карточки без постера.
3. Прогнать этот набор на реальном каталоге: recall@1/@5, precision/false-correction
   rate, доля пустых ответов, комбинации фильтров и оконная граница пагинации.
4. Измерить p50/p95 и число upstream-запросов, ошибки/rate-limit. Mock p50 около
   6 мс НЕ является измерением производительности реального каталога. Смешанный
   подбор может стоить до 2·N запросов, N≤8, плюс ограниченное обогащение.
5. Измерить время от появления известного нового ID в источнике до попадания в
   search/discover через production gateway, включая negative-cache. Не обещать
   фиксированную свежесть только на основании TTL.
6. Прогнать iOS на устройстве: подписи сортировки, коррекция, ввод/очистка/отмена,
   фильтры и ошибки 400/429/502/504, отсутствие скачков/дубликатов между страницами,
   аккаунтная история, artwork, авторизация и воспроизведение.

Ограничения остаются явными: ≤500 страниц на ветку, оконная сортировка после
8-й страницы, словарь наблюдаемых названий, обогащение ≤8 карточек/страница.
Формулировка «поиск находит всё» не используется. Завершение серверной реализации
и успешный mock-preview не заменяют эту приемку.
