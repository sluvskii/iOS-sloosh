import assert from 'node:assert/strict';
import { Hono } from 'hono';
import { mediaRouter } from './src/routes/media';
import { tmdb } from './src/services/tmdb';
import { listCache } from './src/services/cache';

// These are reproductions of CURRENT BUGS, not tests claiming correct behavior.
// Only the public pinned search route/service are real; fixtures replace the
// upstream catalog and artwork/stream adapters. Auth is not mounted or tested.
// Freeze "today" so date-bound reproductions do not depend on runner time.
const NativeDate = Date;
class AuditDate extends NativeDate {
  constructor(value?: string | number) { super(value ?? '2026-10-27T12:00:00.000Z'); }
  static now() { return NativeDate.parse('2026-10-27T12:00:00.000Z'); }
}
globalThis.Date = AuditDate as DateConstructor;

let count = 0;
function observed(name: string, details: unknown) {
  count += 1;
  console.log(`REPRODUCED ${count}: ${name}\n  ${JSON.stringify(details)}`);
}
const app = new Hono();
app.route('/api/v1', mediaRouter);
app.route('/api/v2', mediaRouter);
const get = async (query: string, version = 'v1') => {
  const response = await app.request(`/api/${version}/search?${query}`);
  assert.equal(response.status, 200);
  return (await response.json() as any).data;
};
const rawMovie = (id = 10, extra: object = {}) => ({
  id, title: `Фильм ${id}`, original_title: `Movie ${id}`, media_type: 'movie',
  release_date: '2026-01-01', poster_path: '/poster.jpg', vote_average: 8,
  genre_ids: [18], ...extra,
});
const rawTv = (id = 20, extra: object = {}) => ({
  id, name: `Сериал ${id}`, original_name: `Series ${id}`, media_type: 'tv',
  first_air_date: '2026-01-01', poster_path: '/tv.jpg', vote_average: 8,
  genre_ids: [16], origin_country: ['JP'], ...extra,
});
const page = (results: any[], totalPages = 1) => ({ results, page: 1, total_pages: totalPages, total_results: results.length });
let upstreamCalls: URL[] = [];
let upstreamResponse = (_url: URL): any => page([]);
globalThis.fetch = async (input: any) => {
  const url = new URL(typeof input === 'string' ? input : input.url);
  assert.equal(url.hostname, 'catalog.invalid', 'No live host may be contacted');
  upstreamCalls.push(url);
  return Response.json(upstreamResponse(url));
};
const originalSearch = tmdb.search;
const originalDiscover = tmdb.discover;

// 1: Both aliases run exactly the same title route, not a fuzzy-v1/filter-v2 split.
upstreamResponse = () => page([rawMovie()]);
for (const version of ['v1', 'v2']) {
  listCache.clear();
  await get('query=Матрица', version);
}
assert.deepEqual(upstreamCalls.map(x => x.pathname), ['/3/search/multi', '/3/search/multi']);
observed('v1 and v2 are aliases of the same title search', upstreamCalls.map(x => x.pathname));

// 2: Structured parameters never reach the title-search service.
listCache.clear();
let discoverCalls = 0;
let searchCalls = 0;
tmdb.search = async (query, p) => {
  searchCalls++;
  return { results: [{ id: '10', title: query, type: 'movie', year: 2000, rating: 2 }], page: p, total_pages: 1, total_results: 1 };
};
tmdb.discover = async () => { discoverCalls++; throw Error('Unexpected discover'); };
const ignored = await get('query=Название&type=TV_SERIES&ratingFrom=9&yearFrom=2026&studio=studio_x&countries=Россия');
assert.equal(ignored.results[0].type, 'movie');
assert.equal(ignored.results[0].year, 2000);
assert.equal(discoverCalls, 0);
observed('title search ignores type/rating/year/country/studio', ignored.results);

// 3: Upper-only constraints do not enter discovery at all.
for (const upper of ['yearTo=2020', 'ratingTo=5']) {
  listCache.clear();
  const result = await get(upper);
  assert.deepEqual(result.results, []);
  assert.equal(discoverCalls, 0);
}
observed('yearTo-only and ratingTo-only queries do not invoke discovery', { discoverCalls });

// 4: Upper limits are omitted from the discovery cache key.
listCache.clear();
const bounds: any[] = [];
tmdb.discover = async options => {
  bounds.push(options);
  return { results: [{ id: '1', type: 'movie', title: 'Результат', year: options.yearTo }], page: 1, total_pages: 1, total_results: 1 };
};
await get('type=FILM&yearTo=2020&ratingTo=5');
const reused = await get('type=FILM&yearTo=2026&ratingTo=9');
assert.equal(bounds.length, 1);
assert.equal(reused.results[0].year, 2020);
observed('different yearTo/ratingTo values reuse the same cached response', { requests: bounds.length, secondYear: reused.results[0].year });

// 5: Negative title results have the same one-hour LRU TTL as positive pages.
listCache.clear();
searchCalls = 0;
tmdb.search = async () => {
  searchCalls++;
  return page(searchCalls === 1 ? [] : [{ id: '2', title: 'Уже появился', type: 'movie' }]);
};
await get('query=Новинка');
const negative = await get('query=Новинка');
assert.equal(searchCalls, 1);
assert.deepEqual(negative.results, []);
const ttl = listCache.getRemainingTTL('search:новинка:1');
assert(ttl > 59 * 60 * 1000);
observed('an empty search is cached for roughly one hour in a warm instance', { calls: searchCalls, remainingSeconds: Math.round(ttl / 1000) });

// 6: Studio is neither a trigger for discovery nor an option passed to it.
listCache.clear();
assert.deepEqual((await get('studio=studio_x')).results, []);
let receivedOptions: any;
tmdb.discover = async options => { receivedOptions = options; return page([]); };
await get('type=FILM&studio=studio_x');
assert.equal(receivedOptions.studio, undefined);
observed('studio is not a supported search/discover parameter', receivedOptions);

// Continue against the REAL original service; only fetch is mocked.
tmdb.search = originalSearch;
tmdb.discover = originalDiscover;
upstreamCalls = [];
upstreamResponse = () => page([rawMovie()]);
await tmdb.discover({ genres: 'драма' });
assert.equal(upstreamCalls.length, 1);
assert.equal(upstreamCalls[0].pathname, '/3/discover/movie');
observed('discovery with no type searches films only, not the complete mixed catalog', upstreamCalls.map(x => x.pathname));

upstreamCalls = [];
await tmdb.discover({ order: 'YEAR' });
assert.equal(upstreamCalls[0].searchParams.get('vote_count.gte'), '5');
assert(upstreamCalls[0].searchParams.has('primary_release_date.lte'));
observed('newest sort silently requires five votes and caps release date to today', Object.fromEntries(upstreamCalls[0].searchParams));

// 9: Anime requests reuse movie-specific dates, genres and sort for TV.
upstreamCalls = [];
upstreamResponse = url => page(url.pathname.endsWith('/tv') ? [rawTv()] : [rawMovie()]);
await tmdb.discover({ type: 'ANIME', order: 'YEAR', yearFrom: 2025, yearTo: 2026, genres: 'фантастика' });
const tvRequest = upstreamCalls.find(x => x.pathname.endsWith('/tv'))!;
assert.equal(tvRequest.searchParams.get('first_air_date.gte'), null);
assert.equal(tvRequest.searchParams.get('primary_release_date.gte'), '2025-01-01');
assert.equal(tvRequest.searchParams.get('with_genres'), '878,16');
assert.equal(tvRequest.searchParams.get('sort_by'), 'primary_release_date.desc');
observed('anime TV branch receives movie date/genre/sort parameters', Object.fromEntries(tvRequest.searchParams));

// 10: Interleaving is not a global rating sort.
upstreamResponse = url => page(url.pathname.endsWith('/tv') ? [rawTv(1, { vote_average: 1 })] : [rawMovie(2, { vote_average: 9 })]);
const interleaved = await tmdb.discover({ type: 'ANIME', order: 'RATING' });
assert.deepEqual(interleaved.results.map(x => x.rating), [1, 9]);
observed('combined anime results are interleaved rather than globally sorted', interleaved.results.map(x => ({ type: x.type, rating: x.rating })));

// 11: Discovery excludes every record without a poster, even a dated title.
upstreamResponse = () => page([rawMovie(11, { poster_path: null, backdrop_path: null })]);
const posterless = await tmdb.discover({ type: 'FILM' });
assert.equal(posterless.results.length, 0);
observed('server discovery removes posterless projects before the client sees them', { returned: posterless.results.length });

// 12: Search also excludes announcements without artwork OR any date/year.
upstreamResponse = () => page([rawMovie(12, { poster_path: null, backdrop_path: null, release_date: '' })]);
const announced = await tmdb.search('Анонсировано');
assert.equal(announced.results.length, 0);
observed('undated, posterless announcements are removed by server title search', { returned: announced.results.length });

// 13: A matching person's known-for works appear in a title result bucket.
upstreamResponse = () => page([{ media_type: 'person', name: 'Имя', known_for: [rawMovie(999)] }]);
const fromPerson = await tmdb.search('Имя');
assert.equal(fromPerson.results[0].title, 'Фильм 999');
observed('known-for films of a matched person are mixed into title hits', fromPerson.results.map(x => x.title));

// 14: The route/service do not normalize or correct the actual upstream query.
upstreamCalls = [];
upstreamResponse = () => page([rawMovie()]);
await tmdb.search('  Матирца  ');
assert.equal(upstreamCalls[0].searchParams.get('query'), '  Матирца  ');
observed('the service forwards a typo unchanged without its own fuzzy index/correction', upstreamCalls[0].searchParams.get('query'));

// 15: A normal movie search payload without origin/production country stays unknown.
const sparseCountry = (await tmdb.search('Фильм')).results[0];
assert.deepEqual(sparseCountry.countries, []);
observed('country filtering on title hits needs enrichment when upstream omits country', sparseCountry.countries);

console.log(`\n${count} deterministic source-level reproductions passed. No live catalog, credentials, JWT verification, deployment or production writes tested.`);
